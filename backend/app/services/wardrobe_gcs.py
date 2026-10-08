"""手持ちの服(写真と index.json)を Cloud Storage に保存する `WardrobeStore` の実装(spec 036)。

バケットの中の置き場所(接頭辞の既定は `wardrobe`):
- `<接頭辞>/index.json` … ローカルの index.json と同じ形式。
- `<接頭辞>/images/`    … 写真。

`index.json` は、世代番号(generation)を条件にした書き込みで更新する。他のリクエスト
(別のサーバーを含む)が先に書いていたら読み直してやり直すため、同時に登録しても消えない。

`google-cloud-storage` を import するのはこのファイルだけ(ローカルのときは読み込まない)。
"""

import logging
import threading
from collections.abc import Callable
from functools import lru_cache

from google.api_core.exceptions import NotFound, PreconditionFailed
from google.cloud.storage import Bucket, Client

from app.services.cloth_index import ClothItem
from app.services.wardrobe_store import (
    IMAGES_DIR_NAME,
    StoredEntry,
    WardrobeStoreError,
    dump_index,
    is_valid_image_name,
    mime_type_of,
    new_entry,
    parse_index,
    remove_item,
)

logger = logging.getLogger(__name__)

INDEX_NAME = "index.json"
INDEX_CONTENT_TYPE = "application/json; charset=utf-8"
# 他のリクエストと書き込みがぶつかったときに、読み直してやり直す回数の上限
MAX_WRITE_ATTEMPTS = 5
# 同じサーバーの中では順番に書く(無駄なやり直しを減らすため)
_lock = threading.Lock()


@lru_cache
def _get_client(project: str) -> Client:
    """Cloud Storage のクライアント。認証(ADC)の処理を毎回走らせないよう使い回す。"""
    return Client(project=project or None)


class GcsWardrobeStore:
    """`<バケット>/<接頭辞>/` に index.json と images/ を保存する実装。"""

    def __init__(
        self,
        bucket_name: str,
        prefix: str = "wardrobe",
        project: str = "",
        bucket: Bucket | None = None,
    ) -> None:
        # bucket はテストで偽物を渡すためのもの。渡されなければ最初の操作のときに作る
        # (ここではネットワークにつながない。設定の誤りで起動が止まらないようにするため)
        self.bucket_name = bucket_name
        self.prefix = prefix.strip("/")
        self._project = project
        self._bucket = bucket

    @property
    def index_path(self) -> str:
        """バケットの中の index.json の名前。"""
        return f"{self.prefix}/{INDEX_NAME}" if self.prefix else INDEX_NAME

    def image_path(self, image: str) -> str:
        """バケットの中の写真の名前。"""
        name = f"{IMAGES_DIR_NAME}/{image}"
        return f"{self.prefix}/{name}" if self.prefix else name

    def list_entries(self) -> list[StoredEntry]:
        entries, _ = self._load()
        return entries

    def add(
        self, data: bytes, mime_type: str, items: list[ClothItem], summary: str, model: str
    ) -> StoredEntry:
        entry = new_entry(mime_type, items, summary, model)
        image_path = self.image_path(entry.image)
        # 写真を先に置く(名前は日時 + ランダムで衝突しない)。index.json に載るまでは一覧に出ない
        self._call(
            "写真を保存できませんでした",
            lambda: (
                self._get_bucket().blob(image_path).upload_from_string(data, content_type=mime_type)
            ),
        )
        try:
            self._update_index(lambda entries: entries.append(entry))
        except WardrobeStoreError:
            # 一覧に載らない写真を残さない
            self._delete_quietly(image_path)
            raise
        return entry

    def delete_item(self, item_id: str) -> bool:
        result: tuple[bool, str | None] = (False, None)

        def change(entries: list[StoredEntry]) -> bool:
            nonlocal result
            result = remove_item(entries, item_id)
            return result[0]

        self._update_index(change)
        found, removed_image = result
        if removed_image is not None and is_valid_image_name(removed_image):
            # 一覧からは既に消えているため、写真を消せなくてもエラーにはしない
            self._delete_quietly(self.image_path(removed_image))
        return found

    def read_image(self, image: str) -> tuple[bytes, str] | None:
        if not is_valid_image_name(image):
            return None
        path = self.image_path(image)
        try:
            data = self._get_bucket().blob(path).download_as_bytes()
        except NotFound:
            return None
        except Exception as exc:
            raise self._error("写真を読み込めませんでした", exc) from exc
        return data, mime_type_of(image)

    def _update_index(self, change: Callable[[list[StoredEntry]], object]) -> None:
        """index.json を読み、`change` で書き換えて、世代番号を条件に書き戻す。

        `change` が False を返したら書き戻さない(削除する服が無かったときなど)。
        他のリクエストが先に書いていたら(412)、読み直して最大 MAX_WRITE_ATTEMPTS 回やり直す。
        """
        with _lock:
            for _ in range(MAX_WRITE_ATTEMPTS):
                entries, generation = self._load()
                if change(entries) is False:
                    return
                payload = dump_index(entries)
                try:
                    self._get_bucket().blob(self.index_path).upload_from_string(
                        payload, content_type=INDEX_CONTENT_TYPE, if_generation_match=generation
                    )
                    return
                except PreconditionFailed:
                    logger.info("服のインデックスが同時に更新されたため、読み直します")
                except Exception as exc:
                    raise self._error("服のインデックスを保存できませんでした", exc) from exc
        raise WardrobeStoreError(
            "服のインデックスへの書き込みが他の処理と重なり続けたため、保存できませんでした。"
        )

    def _load(self) -> tuple[list[StoredEntry], int]:
        """index.json と、その世代番号を返す。無ければ ([], 0)(0 は「まだ無ければ書く」の条件)。"""
        text, generation = self._read_index_text()
        if text is None:
            return [], 0
        try:
            return parse_index(text), generation
        except Exception as exc:
            raise WardrobeStoreError(
                f"服のインデックスを読み込めませんでした: gs://{self.bucket_name}/{self.index_path}"
            ) from exc

    def _read_index_text(self) -> tuple[str | None, int]:
        """index.json の中身と世代番号を、同じ世代のものとして読む。無ければ (None, 0)。"""
        for _ in range(MAX_WRITE_ATTEMPTS):
            try:
                blob = self._get_bucket().get_blob(self.index_path)
                if blob is None:
                    return None, 0
                generation = int(blob.generation)
                data = blob.download_as_bytes(if_generation_match=generation)
                return data.decode("utf-8"), generation
            except PreconditionFailed:
                # 世代番号を調べてから読むまでの間に書き換わった。最新を読み直す
                continue
            except WardrobeStoreError:
                raise
            except Exception as exc:
                raise self._error("服のインデックスを読み込めませんでした", exc) from exc
        raise WardrobeStoreError(
            "服のインデックスの読み込み中に更新が続いたため、読み込めませんでした。"
        )

    def _get_bucket(self) -> Bucket:
        if self._bucket is None:
            if not self.bucket_name:
                raise WardrobeStoreError(
                    "WARDROBE_GCS_BUCKET が未設定です(WARDROBE_STORAGE=gcs のときは必須)。"
                )
            try:
                self._bucket = _get_client(self._project).bucket(self.bucket_name)
            except Exception as exc:
                raise self._error("Cloud Storage に接続できませんでした", exc) from exc
        return self._bucket

    def _call(self, message: str, action: Callable[[], object]) -> None:
        try:
            action()
        except WardrobeStoreError:
            raise
        except Exception as exc:
            raise self._error(message, exc) from exc

    def _delete_quietly(self, path: str) -> None:
        try:
            self._get_bucket().blob(path).delete()
        except NotFound:
            pass
        except Exception as exc:
            logger.warning("Cloud Storage の写真を削除できませんでした: %s (%s)", path, exc)

    def _error(self, message: str, exc: Exception) -> WardrobeStoreError:
        logger.warning("%s: %s: %s", message, type(exc).__name__, exc)
        return WardrobeStoreError(f"{message}(Cloud Storage: {type(exc).__name__})")
