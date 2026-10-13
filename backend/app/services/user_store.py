"""ログインできるユーザーの一覧(`users.json`)の保存先(spec 038)。

保存先は手持ちの服(spec 036)と同じ設定 `WARDROBE_STORAGE` に従う。
- local: `<WARDROBE_LOCAL_ROOT>/auth/users.json`
- gcs  : `gs://<WARDROBE_GCS_BUCKET>/auth/users.json`

パスワードはハッシュ(`auth.hash_password`)だけを保存する。ユーザーの追加・削除は
運営のコマンド(`scripts/manage_users.py`)から行い、ログインのたびに読み直すため、
サーバーを再起動しなくてもすぐ反映される。
"""

import json
import threading
from datetime import datetime
from pathlib import Path
from typing import Any, Protocol

from pydantic import BaseModel

from app.core.config import Settings

USERS_PATH = "auth/users.json"
# ローカルの users.json の読み書きを直列にする
_lock = threading.Lock()


class UserStoreError(RuntimeError):
    """ユーザーの一覧を読み書きできない。"""


class UserRecord(BaseModel):
    """登録したユーザー 1 人。password はハッシュ。"""

    password: str
    created_at: str = ""
    updated_at: str = ""


class UserStore(Protocol):
    """ユーザーの一覧の保存先。"""

    def get(self, user_id: str) -> UserRecord | None:
        """ユーザーを返す。いなければ None。"""
        ...

    def list_ids(self) -> list[str]:
        """登録しているユーザー ID の一覧(並びは ID 順)。"""
        ...

    def set_password(self, user_id: str, password_hash: str) -> bool:
        """ユーザーを追加する、またはパスワードを変える。追加したら True、変えたら False。"""
        ...

    def delete(self, user_id: str) -> bool:
        """ユーザーを削除する。いなければ False。"""
        ...


class LocalUserStore:
    """ローカルのファイルに保存する実装。"""

    def __init__(self, path: Path) -> None:
        self.path = path

    def get(self, user_id: str) -> UserRecord | None:
        with _lock:
            return self._load().get(user_id)

    def list_ids(self) -> list[str]:
        with _lock:
            return sorted(self._load())

    def set_password(self, user_id: str, password_hash: str) -> bool:
        with _lock:
            users = self._load()
            added = apply_password(users, user_id, password_hash)
            self._save(users)
            return added

    def delete(self, user_id: str) -> bool:
        with _lock:
            users = self._load()
            if users.pop(user_id, None) is None:
                return False
            self._save(users)
            return True

    def _load(self) -> dict[str, UserRecord]:
        if not self.path.is_file():
            return {}
        try:
            return parse_users(self.path.read_text(encoding="utf-8"))
        except Exception as exc:
            raise UserStoreError(f"ユーザーの一覧を読み込めませんでした: {self.path}") from exc

    def _save(self, users: dict[str, UserRecord]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # 一時ファイルに書いてから置き換える(途中で落ちても壊れないように)
        temp = self.path.with_name(self.path.name + ".tmp")
        temp.write_text(dump_users(users), encoding="utf-8")
        temp.replace(self.path)


def create_user_store(settings: Settings) -> UserStore:
    """設定 `WARDROBE_STORAGE` に従ってユーザーの一覧の保存先を作る。"""
    if settings.wardrobe_storage == "gcs":
        from app.services.user_store_gcs import GcsUserStore

        return GcsUserStore(
            bucket_name=settings.wardrobe_gcs_bucket, project=settings.google_cloud_project
        )
    return LocalUserStore(settings.wardrobe_local_root_path / USERS_PATH)


def apply_password(users: dict[str, UserRecord], user_id: str, password_hash: str) -> bool:
    """`users` にユーザーを追加する、またはパスワードを変える(その場で書き換える)。"""
    now = datetime.now().astimezone().isoformat(timespec="seconds")
    current = users.get(user_id)
    if current is None:
        users[user_id] = UserRecord(password=password_hash, created_at=now, updated_at=now)
        return True
    users[user_id] = current.model_copy(update={"password": password_hash, "updated_at": now})
    return False


def parse_users(text: str) -> dict[str, UserRecord]:
    """users.json の中身を読む。形式が不正なら例外。"""
    payload: dict[str, Any] = json.loads(text)
    return {
        user_id: UserRecord.model_validate(raw) for user_id, raw in payload.get("users", {}).items()
    }


def dump_users(users: dict[str, UserRecord]) -> str:
    """users.json に書く中身を作る。"""
    payload = {"users": {user_id: users[user_id].model_dump() for user_id in sorted(users)}}
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
