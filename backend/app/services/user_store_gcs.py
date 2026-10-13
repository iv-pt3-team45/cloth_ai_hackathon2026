"""ログインできるユーザーの一覧を Cloud Storage に保存する実装(spec 038)。

`gs://<バケット>/auth/users.json` に置く。手持ちの服(spec 036)と同じく、世代番号を条件にした
書き込みで更新し、運営のコマンドが同時に動いても壊さない。
"""

import logging
from collections.abc import Callable

from google.api_core.exceptions import PreconditionFailed
from google.cloud.storage import Bucket

from app.services.user_store import (
    USERS_PATH,
    UserRecord,
    UserStoreError,
    apply_password,
    dump_users,
    parse_users,
)
from app.services.wardrobe_gcs import INDEX_CONTENT_TYPE, MAX_WRITE_ATTEMPTS, _get_client

logger = logging.getLogger(__name__)


class GcsUserStore:
    """`gs://<バケット>/auth/users.json` に保存する実装。"""

    def __init__(self, bucket_name: str, project: str = "", bucket: Bucket | None = None) -> None:
        # bucket はテストで偽物を渡すためのもの。渡されなければ最初の操作のときに作る
        self.bucket_name = bucket_name
        self._project = project
        self._bucket = bucket

    def get(self, user_id: str) -> UserRecord | None:
        users, _ = self._load()
        return users.get(user_id)

    def list_ids(self) -> list[str]:
        users, _ = self._load()
        return sorted(users)

    def set_password(self, user_id: str, password_hash: str) -> bool:
        result = False

        def change(users: dict[str, UserRecord]) -> bool:
            nonlocal result
            result = apply_password(users, user_id, password_hash)
            return True

        self._update(change)
        return result

    def delete(self, user_id: str) -> bool:
        return self._update(lambda users: users.pop(user_id, None) is not None)

    def _update(self, change: Callable[[dict[str, UserRecord]], bool]) -> bool:
        """users.json を読み、`change` で書き換えて、世代番号を条件に書き戻す。

        `change` が False なら書き戻さずに False を返す。
        """
        for _ in range(MAX_WRITE_ATTEMPTS):
            users, generation = self._load()
            if not change(users):
                return False
            try:
                self._get_bucket().blob(USERS_PATH).upload_from_string(
                    dump_users(users),
                    content_type=INDEX_CONTENT_TYPE,
                    if_generation_match=generation,
                )
                return True
            except PreconditionFailed:
                logger.info("ユーザーの一覧が同時に更新されたため、読み直します")
            except Exception as exc:
                raise UserStoreError(
                    f"ユーザーの一覧を保存できませんでした(Cloud Storage: {type(exc).__name__})"
                ) from exc
        raise UserStoreError("ユーザーの一覧への書き込みが他の処理と重なり続けました。")

    def _load(self) -> tuple[dict[str, UserRecord], int]:
        """users.json と世代番号。無ければ ({}, 0)。"""
        try:
            blob = self._get_bucket().get_blob(USERS_PATH)
            if blob is None:
                return {}, 0
            generation = int(blob.generation)
            text = blob.download_as_bytes(if_generation_match=generation).decode("utf-8")
        except UserStoreError:
            raise
        except Exception as exc:
            raise UserStoreError(
                f"ユーザーの一覧を読み込めませんでした(Cloud Storage: {type(exc).__name__})"
            ) from exc
        try:
            return parse_users(text), generation
        except Exception as exc:
            raise UserStoreError(
                f"ユーザーの一覧を読み込めませんでした: gs://{self.bucket_name}/{USERS_PATH}"
            ) from exc

    def _get_bucket(self) -> Bucket:
        if self._bucket is None:
            if not self.bucket_name:
                raise UserStoreError(
                    "WARDROBE_GCS_BUCKET が未設定です(WARDROBE_STORAGE=gcs のときは必須)。"
                )
            try:
                self._bucket = _get_client(self._project).bucket(self.bucket_name)
            except Exception as exc:
                raise UserStoreError(
                    f"Cloud Storage に接続できませんでした({type(exc).__name__})"
                ) from exc
        return self._bucket
