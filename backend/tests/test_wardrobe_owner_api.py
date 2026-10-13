"""手持ちの服・コーデ提案の API が、トークンの持ち主ごとに分かれること(spec 038)のテスト。

トークンの確認は差し替えず、実際にログイン・ゲストの API でもらったトークンを使う。
"""

from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app
from app.services.auth import AuthService, get_auth_service, hash_password
from app.services.outfit import OutfitService, get_outfit_service
from app.services.user_store import LocalUserStore
from app.services.wardrobe_registry import WardrobeService, get_wardrobe_service
from tests.outfit_stub import make_culture, make_live, make_video, unknown_venue
from tests.wardrobe_stub import fake_client, image_body

SECRET = "test-secret-key-0123456789abcdef"
ITEM = {"category": "Tシャツ", "material": "綿", "shape": "半袖", "colors": ["白"]}


def make_api(tmp_path: Path) -> TestClient:
    settings = Settings(
        wardrobe_local_root=str(tmp_path),
        auth_secret_key=SECRET,
        cloth_index_model="test-model",
    )
    users = LocalUserStore(tmp_path / "auth" / "users.json")
    users.set_password("demo01", hash_password("pass-01"))
    users.set_password("demo02", hash_password("pass-02"))
    auth = AuthService(settings, users=users)
    # 保存先は差し替えない(持ち主ごとに作られることを確かめるため)
    wardrobe = WardrobeService(settings=settings, client=fake_client())
    outfit = OutfitService(settings=settings, client=object(), venue_lookup=unknown_venue)  # type: ignore[arg-type]
    app = create_app()
    app.dependency_overrides[get_auth_service] = lambda: auth
    app.dependency_overrides[get_wardrobe_service] = lambda: wardrobe
    app.dependency_overrides[get_outfit_service] = lambda: outfit
    return TestClient(app)


def login(api: TestClient, user_id: str, password: str) -> dict[str, str]:
    res = api.post("/api/v1/auth/login", json={"user_id": user_id, "password": password})
    return {"Authorization": f"Bearer {res.json()['token']}"}


def guest(api: TestClient) -> dict[str, str]:
    return {"Authorization": f"Bearer {api.post('/api/v1/auth/guest').json()['token']}"}


def register(api: TestClient, headers: dict[str, str], category: str) -> dict[str, Any]:
    res = api.post(
        "/api/v1/wardrobe/items",
        json={"image": image_body(), "items": [{**ITEM, "category": category}]},
        headers=headers,
    )
    assert res.status_code == 201
    item: dict[str, Any] = res.json()["items"][0]
    return item


def categories(api: TestClient, headers: dict[str, str]) -> list[str]:
    res = api.get("/api/v1/wardrobe/items", headers=headers)
    assert res.status_code == 200
    return [item["category"] for item in res.json()["items"]]


def test_clothes_are_separated_per_owner(tmp_path: Path) -> None:
    """AC-8: ユーザー A・B・ゲストは、自分の服だけが見え、他の人の服は取得・削除できない。"""
    api = make_api(tmp_path)
    user_a = login(api, "demo01", "pass-01")
    user_b = login(api, "demo02", "pass-02")
    guest_1 = guest(api)
    guest_2 = guest(api)

    item_a = register(api, user_a, "A の服")
    register(api, user_b, "B の服")
    register(api, guest_1, "ゲストの服")

    assert categories(api, user_a) == ["A の服"]
    assert categories(api, user_b) == ["B の服"]
    assert categories(api, guest_1) == ["ゲストの服"]
    assert categories(api, guest_2) == []

    image = f"/api/v1/wardrobe/images/{item_a['image']}"
    assert api.get(image, headers=user_a).status_code == 200
    assert api.get(image, headers=user_b).status_code == 404
    assert api.delete(f"/api/v1/wardrobe/items/{item_a['id']}", headers=user_b).status_code == 404
    assert categories(api, user_a) == ["A の服"]

    # AC-9: 置き場所が持ち主ごとに分かれている
    assert (tmp_path / "users" / "demo01" / "wardrobe" / "index.json").is_file()
    assert (tmp_path / "users" / "demo02" / "wardrobe" / "index.json").is_file()
    assert len(list((tmp_path / "guests").iterdir())) == 1


def test_same_user_sees_clothes_from_another_login(tmp_path: Path) -> None:
    """AC-4: 別のブラウザで同じユーザーとしてログインしても、同じ服が見える。"""
    api = make_api(tmp_path)
    register(api, login(api, "demo01", "pass-01"), "A の服")

    assert categories(api, login(api, "demo01", "pass-01")) == ["A の服"]


@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        ("GET", "/api/v1/wardrobe/items", None),
        ("POST", "/api/v1/wardrobe/items", {"image": image_body(), "items": [ITEM]}),
        ("DELETE", "/api/v1/wardrobe/items/x", None),
        ("GET", "/api/v1/wardrobe/images/cloth-1.jpg", None),
        ("POST", "/api/v1/outfit/image", {"item_ids": ["x"]}),
    ],
)
def test_wardrobe_and_outfit_require_token(
    tmp_path: Path, method: str, path: str, body: dict[str, Any] | None
) -> None:
    """AC-10・AC-13: トークンが無い・壊れていると 401 で、何も保存されない。"""
    api = make_api(tmp_path)

    for headers in ({}, {"Authorization": "Bearer broken"}):
        res = api.request(method, path, json=body, headers=headers)
        assert res.status_code == 401
    assert not (tmp_path / "users").exists()
    assert not (tmp_path / "guests").exists()


def test_suggest_requires_token(tmp_path: Path) -> None:
    api = make_api(tmp_path)
    body = {
        "video": make_video().model_dump(mode="json"),
        "culture": make_culture().model_dump(mode="json"),
        "live": make_live().model_dump(mode="json"),
    }

    assert api.post("/api/v1/outfit/suggest", json=body).status_code == 401


def test_analyze_does_not_require_token(tmp_path: Path) -> None:
    """解析は保存しないため、トークンは不要のまま。"""
    api = make_api(tmp_path)

    res = api.post("/api/v1/wardrobe/analyze", json={"image": image_body()})

    assert res.status_code == 200


def test_deleted_user_token_becomes_401(tmp_path: Path) -> None:
    api = make_api(tmp_path)
    headers = login(api, "demo01", "pass-01")
    LocalUserStore(tmp_path / "auth" / "users.json").delete("demo01")

    assert api.get("/api/v1/wardrobe/items", headers=headers).status_code == 401
