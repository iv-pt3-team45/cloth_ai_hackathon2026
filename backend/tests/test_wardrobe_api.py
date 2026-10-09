"""手持ちの服の登録 API のテスト(Gemini はフェイクのクライアントで差し替える)。"""

from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient
from google.genai import errors

from app.main import create_app
from app.services.wardrobe import build_wardrobe_tools
from app.services.wardrobe_registry import get_wardrobe_service
from tests.auth_stub import as_owner
from tests.wardrobe_stub import JPEG, PNG, fake_client, image_body, make_service, make_settings


def make_api(tmp_path: Path, client: Any = None) -> TestClient:
    app = create_app()
    service = make_service(tmp_path, client)
    app.dependency_overrides[get_wardrobe_service] = lambda: service
    as_owner(app)
    return TestClient(app)


ITEM = {
    "category": "Tシャツ",
    "material": "綿",
    "shape": "半袖",
    "colors": ["白"],
    "pattern": "無地",
    "style": "カジュアル",
    "notes": "",
    "seasons": ["春", "夏"],
    "warmth": "薄手",
    "occasions": ["普段着", "ライブ・フェス"],
}


def register(api: TestClient, items: list[dict[str, Any]] | None = None) -> Any:
    return api.post(
        "/api/v1/wardrobe/items",
        json={"image": image_body(), "items": items if items is not None else [ITEM]},
    )


def test_analyze_returns_items_without_saving(tmp_path: Path) -> None:
    """AC-2 / AC-3 / AC-7"""
    api = make_api(tmp_path)

    res = api.post("/api/v1/wardrobe/analyze", json={"image": image_body()})

    assert res.status_code == 200
    body = res.json()
    assert [item["category"] for item in body["items"]] == ["Tシャツ", "ジーンズ"]
    assert body["items"][1]["warmth"] == "普通"
    assert body["model"] == "test-model"
    assert api.get("/api/v1/wardrobe/items").json()["count"] == 0


def test_analyze_rejects_invalid_images(tmp_path: Path) -> None:
    """AC-11: 形式・中身・大きさが不正な写真は、その写真だけエラーになる。"""
    api = make_api(tmp_path)

    def analyze(body: dict[str, str]) -> int:
        return api.post("/api/v1/wardrobe/analyze", json={"image": body}).status_code

    assert analyze({"mime_type": "image/heic", "data": "AAAA"}) == 422
    assert analyze(image_body(PNG, "image/jpeg")) == 400
    assert analyze({"mime_type": "image/jpeg", "data": "%%%"}) == 400
    assert analyze(image_body(JPEG + b"x" * 5000)) == 413


def test_analyze_maps_gemini_errors(tmp_path: Path) -> None:
    """AC-12"""

    def quota(**kwargs: Any) -> Any:
        raise errors.ClientError(429, {"error": {"code": 429, "status": "RESOURCE_EXHAUSTED"}})

    def broken(**kwargs: Any) -> Any:
        raise errors.ServerError(500, {"error": {"code": 500}})

    body = {"image": image_body()}
    res = make_api(tmp_path, fake_client(quota)).post("/api/v1/wardrobe/analyze", json=body)
    assert res.status_code == 503
    assert "クォータ" in res.json()["detail"]
    res = make_api(tmp_path, fake_client(broken)).post("/api/v1/wardrobe/analyze", json=body)
    assert res.status_code == 502


def test_register_list_and_image(tmp_path: Path) -> None:
    """AC-6 / AC-8: 保存すると一覧と写真の取得に出る。"""
    api = make_api(tmp_path)

    res = register(api)

    assert res.status_code == 201
    saved = res.json()["items"][0]
    listed = api.get("/api/v1/wardrobe/items").json()
    assert listed["count"] == 1
    assert listed["items"][0]["id"] == saved["id"]
    assert listed["items"][0]["occasions"] == ["普段着", "ライブ・フェス"]
    image = api.get(f"/api/v1/wardrobe/images/{saved['image']}")
    assert image.status_code == 200
    assert image.content == JPEG
    assert image.headers["content-type"] == "image/jpeg"


def test_register_validates_items(tmp_path: Path) -> None:
    api = make_api(tmp_path)

    assert register(api, items=[]).status_code == 422
    assert register(api, items=[{**ITEM, "category": ""}]).status_code == 422
    assert register(api, items=[{**ITEM, "seasons": ["梅雨"]}]).status_code == 422


def test_delete_item(tmp_path: Path) -> None:
    """AC-9"""
    api = make_api(tmp_path)
    saved = register(api).json()["items"][0]

    assert api.delete(f"/api/v1/wardrobe/items/{saved['id']}").status_code == 204
    assert api.get("/api/v1/wardrobe/items").json()["count"] == 0
    assert api.delete(f"/api/v1/wardrobe/items/{saved['id']}").status_code == 404
    assert api.get(f"/api/v1/wardrobe/images/{saved['image']}").status_code == 404


def test_image_rejects_unsafe_names(tmp_path: Path) -> None:
    api = make_api(tmp_path)
    register(api)

    assert api.get("/api/v1/wardrobe/images/..").status_code == 404
    assert api.get("/api/v1/wardrobe/images/index.json").status_code == 404


def test_registered_clothes_are_visible_to_agent(tmp_path: Path) -> None:
    """AC-10: 登録した服をチャットのエージェント(spec 006 のツール)が参照できる。"""
    api = make_api(tmp_path)
    register(api)

    list_wardrobe, search_wardrobe = build_wardrobe_tools(make_settings(tmp_path))

    listed = list_wardrobe()
    assert listed["status"] == "ok"
    assert listed["items"][0]["category"] == "Tシャツ"
    assert search_wardrobe("ライブ・フェス")["count"] == 1
