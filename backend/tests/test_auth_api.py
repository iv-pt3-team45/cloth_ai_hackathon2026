"""ログイン・ゲスト・me の API(spec 038)のテスト。"""

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app
from app.services.auth import AuthService, get_auth_service, hash_password
from app.services.user_store import LocalUserStore

SECRET = "test-secret-key-0123456789abcdef"


def make_api(tmp_path: Path, **settings: object) -> tuple[TestClient, LocalUserStore]:
    values: dict[str, object] = {"wardrobe_local_root": str(tmp_path), "auth_secret_key": SECRET}
    values.update(settings)
    users = LocalUserStore(tmp_path / "auth" / "users.json")
    service = AuthService(Settings(**values), users=users)  # type: ignore[arg-type]
    app = create_app()
    app.dependency_overrides[get_auth_service] = lambda: service
    return TestClient(app), users


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_login_returns_token_usable_for_me(tmp_path: Path) -> None:
    """AC-1"""
    api, users = make_api(tmp_path)
    users.set_password("demo01", hash_password("pass-01"))

    res = api.post("/api/v1/auth/login", json={"user_id": "demo01", "password": "pass-01"})

    assert res.status_code == 200
    body = res.json()
    assert body["kind"] == "user"
    assert body["user_id"] == "demo01"
    assert body["expires_at"]
    me = api.get("/api/v1/auth/me", headers=bearer(body["token"]))
    assert me.status_code == 200
    assert me.json()["user_id"] == "demo01"


@pytest.mark.parametrize(("user_id", "password"), [("demo01", "wrong"), ("nobody", "pass-01")])
def test_login_failure_is_401_with_same_message(
    tmp_path: Path, user_id: str, password: str
) -> None:
    """AC-2"""
    api, users = make_api(tmp_path)
    users.set_password("demo01", hash_password("pass-01"))

    res = api.post("/api/v1/auth/login", json={"user_id": user_id, "password": password})

    assert res.status_code == 401
    assert res.json()["detail"] == "ユーザー ID またはパスワードが違います。"


def test_login_rejects_empty_input(tmp_path: Path) -> None:
    api, _ = make_api(tmp_path)

    assert api.post("/api/v1/auth/login", json={"user_id": "", "password": ""}).status_code == 422


def test_guest_returns_token(tmp_path: Path) -> None:
    api, _ = make_api(tmp_path)

    res = api.post("/api/v1/auth/guest")

    assert res.status_code == 200
    body = res.json()
    assert body["kind"] == "guest"
    assert body["user_id"] is None
    me = api.get("/api/v1/auth/me", headers=bearer(body["token"]))
    assert me.json() == {"kind": "guest", "user_id": None, "expires_at": None}


@pytest.mark.parametrize(
    "headers",
    [{}, {"Authorization": "Bearer broken"}, {"Authorization": "Basic abc"}],
)
def test_me_without_valid_token_is_401(tmp_path: Path, headers: dict[str, str]) -> None:
    """AC-10"""
    api, _ = make_api(tmp_path)

    res = api.get("/api/v1/auth/me", headers=headers)

    assert res.status_code == 401
    assert res.headers["www-authenticate"] == "Bearer"


def test_missing_secret_in_prod_is_503(tmp_path: Path) -> None:
    api, _ = make_api(tmp_path, auth_secret_key="", environment="prod")

    assert api.post("/api/v1/auth/guest").status_code == 503
