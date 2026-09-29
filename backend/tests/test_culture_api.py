"""カルチャー情報 API のテスト(Gemini はフェイクのクライアントで差し替える)。"""

import asyncio
from typing import Any

from fastapi.testclient import TestClient
from google.genai import errors

from app.main import create_app
from app.services.culture import get_culture_service
from tests.culture_stub import default_responder, kind, make_client, make_service, make_video


def make_api(respond: Any = default_responder, **settings: Any) -> TestClient:
    app = create_app()
    service = make_service(make_client(respond), **settings)
    app.dependency_overrides[get_culture_service] = lambda: service
    return TestClient(app)


def research(client: TestClient, body: dict[str, Any] | None = None) -> Any:
    payload = body if body is not None else {"video": make_video().model_dump(mode="json")}
    return client.post("/api/v1/culture/research", json=payload)


def fail_research(error: Exception) -> Any:
    def respond(call: dict[str, Any]) -> Any:
        if kind(call) == "research":
            raise error
        return default_responder(call)

    return respond


def test_research_returns_culture() -> None:
    res = research(make_api())

    assert res.status_code == 200
    body = res.json()
    assert body["identified"] is True
    assert body["fashion"]["colors"] == ["黒", "白"]
    assert body["background"]["genres"] == ["J-POP"]
    assert body["mv_outfit"]["status"] == "ok"
    assert body["mv_outfit"]["looks"][0]["items"][0]["category"] == "ワンピース"
    assert body["sources"][0] == {
        "index": 1,
        "title": "記事A",
        "url": "https://example.com/a",
        "domain": "example.com",
    }
    assert body["search_suggestions_html"]
    assert body["model"] == "test-model"


def test_research_rejects_missing_video() -> None:
    assert research(make_api(), body={}).status_code == 422


def test_research_returns_502_for_gemini_error() -> None:
    """AC-9"""
    res = research(make_api(fail_research(errors.ServerError(500, {"error": {"code": 500}}))))

    assert res.status_code == 502
    assert "Web での調査に失敗しました" in res.json()["detail"]


def test_research_returns_503_for_quota_error() -> None:
    """AC-9"""
    error = errors.ClientError(429, {"error": {"code": 429, "status": "RESOURCE_EXHAUSTED"}})

    res = research(make_api(fail_research(error)))

    assert res.status_code == 503
    assert "クォータ" in res.json()["detail"]


def test_research_returns_504_for_timeout() -> None:
    """AC-9"""

    async def slow(call: dict[str, Any]) -> Any:
        await asyncio.sleep(10)

    res = research(make_api(slow, culture_timeout=0.05))

    assert res.status_code == 504
    assert "秒以内" in res.json()["detail"]
