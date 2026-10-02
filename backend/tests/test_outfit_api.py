"""コーデ提案 API のテスト(Gemini はフェイクのクライアントで差し替える)。"""

import asyncio
from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient
from google.genai import errors

from app.main import create_app
from app.services.outfit import get_outfit_service
from tests.outfit_stub import (
    make_culture,
    make_live,
    make_service,
    make_settings,
    make_video,
    register_clothes,
    responder,
    suggestion,
)


def make_api(tmp_path: Path, respond: Any, register: bool = True, **settings: Any) -> Any:
    config = make_settings(tmp_path, **settings)
    ids = register_clothes(config) if register else {}
    service, _ = make_service(config, respond)
    app = create_app()
    app.dependency_overrides[get_outfit_service] = lambda: service
    return TestClient(app), ids


def suggest_body() -> dict[str, Any]:
    return {
        "video": make_video().model_dump(mode="json"),
        "culture": make_culture().model_dump(mode="json"),
        "live": make_live().model_dump(mode="json"),
    }


def test_suggest_and_image(tmp_path: Path) -> None:
    """AC-9 / AC-11: 提案 → その服で画像の生成。"""
    holder: dict[str, Any] = {}

    def respond(call: dict[str, Any]) -> Any:
        return responder(suggestion(*holder["ids"]))(call)

    api, ids = make_api(tmp_path, respond)
    holder["ids"] = [ids["Tシャツ"], ids["ジーンズ"]]

    res = api.post("/api/v1/outfit/suggest", json=suggest_body())

    assert res.status_code == 200
    body = res.json()
    assert [item["category"] for item in body["items"]] == ["Tシャツ", "ジーンズ"]
    assert body["items"][0]["reason"]
    assert body["excluded_count"] == 0

    image = api.post(
        "/api/v1/outfit/image",
        json={"item_ids": [item["id"] for item in body["items"]], "title": body["title"]},
    )
    assert image.status_code == 200
    assert image.json()["data"]
    assert image.json()["model"] == "test-image"


def test_suggest_without_culture(tmp_path: Path) -> None:
    holder: dict[str, Any] = {}
    api, ids = make_api(tmp_path, lambda call: responder(suggestion(holder["id"]))(call))
    holder["id"] = ids["Tシャツ"]

    res = api.post("/api/v1/outfit/suggest", json={**suggest_body(), "culture": None})

    assert res.status_code == 200


def test_suggest_rejects_empty_wardrobe(tmp_path: Path) -> None:
    api, _ = make_api(tmp_path, responder(suggestion()), register=False)

    res = api.post("/api/v1/outfit/suggest", json=suggest_body())

    assert res.status_code == 400
    assert "登録されていません" in res.json()["detail"]


def test_suggest_requires_live(tmp_path: Path) -> None:
    api, _ = make_api(tmp_path, responder(suggestion()))
    body = suggest_body()
    del body["live"]

    assert api.post("/api/v1/outfit/suggest", json=body).status_code == 422


def test_suggest_maps_errors(tmp_path: Path) -> None:
    def quota(call: dict[str, Any]) -> Any:
        raise errors.ClientError(429, {"error": {"code": 429, "status": "RESOURCE_EXHAUSTED"}})

    def broken(call: dict[str, Any]) -> Any:
        raise errors.ServerError(500, {"error": {"code": 500}})

    async def slow(call: dict[str, Any]) -> Any:
        await asyncio.sleep(10)

    assert (
        make_api(tmp_path / "a", quota)[0]
        .post("/api/v1/outfit/suggest", json=suggest_body())
        .status_code
        == 503
    )
    assert (
        make_api(tmp_path / "b", broken)[0]
        .post("/api/v1/outfit/suggest", json=suggest_body())
        .status_code
        == 502
    )
    assert (
        make_api(tmp_path / "c", slow, outfit_timeout=0.05)[0]
        .post("/api/v1/outfit/suggest", json=suggest_body())
        .status_code
        == 504
    )


def test_image_rejects_unknown_items(tmp_path: Path) -> None:
    api, _ = make_api(tmp_path, responder())

    res = api.post("/api/v1/outfit/image", json={"item_ids": ["not-owned"]})

    assert res.status_code == 400


def test_image_requires_items(tmp_path: Path) -> None:
    api, _ = make_api(tmp_path, responder())

    assert api.post("/api/v1/outfit/image", json={"item_ids": []}).status_code == 422
