"""ログイン(spec 038)のテスト用スタブ。手持ちの服・コーデ提案の API の持ち主を固定する。"""

from fastapi import FastAPI

from app.api.deps import current_owner
from app.services.auth import Owner

TEST_OWNER = Owner(kind="user", id="tester")


def as_owner(app: FastAPI, owner: Owner = TEST_OWNER) -> FastAPI:
    """トークンの確認を飛ばし、`owner` が呼んだことにする。"""
    app.dependency_overrides[current_owner] = lambda: owner
    return app
