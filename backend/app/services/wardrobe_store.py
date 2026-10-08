"""登録した手持ちの服(写真とインデックス)の保存(spec 010)。

保存処理は `WardrobeStore`(Protocol)で抽象化し、ローカルファイルの実装(本ファイル)と
Cloud Storage の実装(`wardrobe_gcs.py`。spec 036)を持つ。どちらを使うかは設定
`WARDROBE_STORAGE` で決まり、`create_wardrobe_store` が選ぶ。

ローカルの保存形式(`CLOTH_INDEX_PATH` のフォルダ。Cloud Storage でも同じ形で置く):
- `index.json` … spec 005 の形式に、服ごとの `id` を足したもの。005 の `load_index` と
  006 の `load_wardrobe` は `id` を無視してそのまま読める(エージェントも登録した服を参照できる)。
- `images/`    … 写真。
"""

import json
import logging
import re
import secrets
import threading
from datetime import datetime
from pathlib import Path
from typing import Any, Protocol

from pydantic import BaseModel, Field

from app.core.config import Settings
from app.services.cloth_index import ClothItem
from app.services.media import build_file_name

logger = logging.getLogger(__name__)

IMAGES_DIR_NAME = "images"
# 写真のファイル名として受け付ける文字(保存先のフォルダの外を指せないようにする)
IMAGE_NAME = re.compile(r"^[A-Za-z0-9._-]+$")
_MIME_BY_SUFFIX = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}
# index.json の読み書きを直列にする(同時に保存・削除されても壊さないため)
_lock = threading.Lock()


class WardrobeStoreError(RuntimeError):
    """保存先を読み書きできない(index.json が壊れているなど)。"""


class StoredCloth(ClothItem):
    """保存した服 1 点。削除のために ID を持つ。"""

    id: str


class StoredEntry(BaseModel):
    """保存した写真 1 枚ぶんの記録(spec 005 の ClothIndexEntry と同じ形 + 服の ID)。"""

    image: str
    items: list[StoredCloth] = Field(default_factory=list)
    summary: str = ""
    model: str = ""
    analyzed_at: str = ""


class WardrobeStore(Protocol):
    """手持ちの服の保存先。ローカルファイル以外(Cloud など)に移すときはこれを実装する。"""

    def list_entries(self) -> list[StoredEntry]:
        """保存した写真と服を、保存した順に返す。"""
        ...

    def add(
        self, data: bytes, mime_type: str, items: list[ClothItem], summary: str, model: str
    ) -> StoredEntry:
        """写真 1 枚と、その写真に写った服を保存する。"""
        ...

    def delete_item(self, item_id: str) -> bool:
        """服 1 点を削除する。写真に服が残らなければ写真も消す。見つからなければ False。"""
        ...

    def read_image(self, image: str) -> tuple[bytes, str] | None:
        """保存した写真を (バイト列, MIME タイプ) で返す。無ければ None。"""
        ...


class LocalWardrobeStore:
    """`index.json` と `images/` をローカルのフォルダに保存する実装。"""

    def __init__(self, index_file: Path) -> None:
        self.index_file = index_file
        self.images_dir = index_file.parent / IMAGES_DIR_NAME

    def list_entries(self) -> list[StoredEntry]:
        with _lock:
            try:
                return self._load()
            except WardrobeStoreError:
                logger.warning("服のインデックスを読み込めませんでした: %s", self.index_file)
                return []

    def add(
        self, data: bytes, mime_type: str, items: list[ClothItem], summary: str, model: str
    ) -> StoredEntry:
        entry = new_entry(mime_type, items, summary, model)
        with _lock:
            # 壊れた index.json を上書きして登録済みの服を失わないよう、先に読んで確かめる
            entries = self._load()
            self.images_dir.mkdir(parents=True, exist_ok=True)
            (self.images_dir / entry.image).write_bytes(data)
            entries.append(entry)
            self._save(entries)
        return entry

    def delete_item(self, item_id: str) -> bool:
        with _lock:
            entries = self._load()
            found, removed_image = remove_item(entries, item_id)
            if not found:
                return False
            if removed_image is not None:
                image = self._image_file(removed_image)
                if image is not None:
                    image.unlink(missing_ok=True)
            self._save(entries)
            return True

    def read_image(self, image: str) -> tuple[bytes, str] | None:
        path = self._image_file(image)
        if path is None or not path.is_file():
            return None
        return path.read_bytes(), mime_type_of(image)

    def _image_file(self, image: str) -> Path | None:
        """写真のパス。ファイル名として不正なら None(保存先の外を指させない)。"""
        if not is_valid_image_name(image):
            return None
        return self.images_dir / image

    def _load(self) -> list[StoredEntry]:
        if not self.index_file.is_file():
            return []
        try:
            return parse_index(self.index_file.read_text(encoding="utf-8"))
        except Exception as exc:
            raise WardrobeStoreError(
                f"服のインデックスを読み込めませんでした: {self.index_file}"
            ) from exc

    def _save(self, entries: list[StoredEntry]) -> None:
        self.index_file.parent.mkdir(parents=True, exist_ok=True)
        # 一時ファイルに書いてから置き換える(途中で落ちても index.json が壊れないように)
        temp = self.index_file.with_name(self.index_file.name + ".tmp")
        temp.write_text(dump_index(entries), encoding="utf-8")
        temp.replace(self.index_file)


def create_wardrobe_store(settings: Settings) -> WardrobeStore:
    """設定 `WARDROBE_STORAGE` に従って保存先を作る(spec 036)。

    既定(local)はローカルのフォルダ。gcs のときだけ Cloud Storage のライブラリを読み込む。
    """
    if settings.wardrobe_storage == "gcs":
        from app.services.wardrobe_gcs import GcsWardrobeStore

        return GcsWardrobeStore(
            bucket_name=settings.wardrobe_gcs_bucket,
            prefix=settings.wardrobe_gcs_prefix,
            project=settings.google_cloud_project,
        )
    return LocalWardrobeStore(settings.cloth_index_file)


def describe_wardrobe_location(settings: Settings) -> str:
    """保存先の場所を人が読める形で返す(エージェントの案内文・ログ用)。"""
    if settings.wardrobe_storage == "gcs":
        prefix = settings.wardrobe_gcs_prefix.strip("/")
        return f"gs://{settings.wardrobe_gcs_bucket}/{prefix}/index.json"
    return str(settings.cloth_index_file)


def new_entry(mime_type: str, items: list[ClothItem], summary: str, model: str) -> StoredEntry:
    """これから保存する写真 1 枚ぶんの記録を作る(写真のファイル名と服の ID を割り当てる)。"""
    return StoredEntry(
        image=build_file_name("cloth", mime_type, ".jpg"),
        items=[StoredCloth(id=secrets.token_hex(6), **item.model_dump()) for item in items],
        summary=summary,
        model=model,
        analyzed_at=datetime.now().astimezone().isoformat(timespec="seconds"),
    )


def remove_item(entries: list[StoredEntry], item_id: str) -> tuple[bool, str | None]:
    """`entries` から服 1 点を取り除く(その場で書き換える)。

    Returns:
        (見つかったか, 服が残らず記録ごと消えた写真のファイル名。消えなければ None)
    """
    for entry in entries:
        remaining = [item for item in entry.items if item.id != item_id]
        if len(remaining) == len(entry.items):
            continue
        if remaining:
            entry.items = remaining
            return True, None
        entries.remove(entry)
        return True, entry.image
    return False, None


def is_valid_image_name(image: str) -> bool:
    """写真のファイル名として受け付けるか(保存先のフォルダの外を指させない)。"""
    return bool(IMAGE_NAME.match(image)) and image not in (".", "..")


def mime_type_of(image: str) -> str:
    """写真のファイル名(拡張子)から MIME タイプを決める。"""
    return _MIME_BY_SUFFIX.get(Path(image).suffix.lower(), "image/jpeg")


def parse_index(text: str) -> list[StoredEntry]:
    """index.json の中身を読む。形式が不正なら例外(呼び出し側で WardrobeStoreError にする)。"""
    payload = json.loads(text)
    return [_to_entry(raw) for raw in payload.get("entries", [])]


def dump_index(entries: list[StoredEntry]) -> str:
    """index.json に書く中身を作る(spec 005 の形式 + 服の ID)。"""
    payload = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "model": entries[-1].model if entries else "",
        "source_dir": "app",
        "count": len(entries),
        "entries": [entry.model_dump() for entry in entries],
    }
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def _to_entry(raw: dict[str, Any]) -> StoredEntry:
    """index.json の 1 件を読む。

    ID の無い服(spec 005 の CLI で作ったもの)には ID を割り当てる。
    必須の項目が欠けた服も、1 点のためにインデックス全体が読めなくならないよう空文字で補う。
    """
    image = str(raw.get("image", ""))
    required = {"category": "", "material": "", "shape": ""}
    items = [
        {**required, **item, "id": item.get("id") or f"{image}#{i}"}
        for i, item in enumerate(raw.get("items", []))
    ]
    return StoredEntry.model_validate({**raw, "items": items})
