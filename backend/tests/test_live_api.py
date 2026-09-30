"""ライブ情報の検索 API のテスト(Gemini はフェイクのクライアントで差し替える)。"""

import asyncio
from typing import Any

from fastapi.testclient import TestClient
from google.genai import errors

from app.main import create_app
from app.services.live import get_live_service
from tests.gemini_stub import calls_of
from tests.live_stub import make_client, make_service


def make_api(respond: Any = None, **settings: Any) -> tuple[TestClient, Any]:
    app = create_app()
    client = make_client(respond)
    service = make_service(client, **settings)
    app.dependency_overrides[get_live_service] = lambda: service
    return TestClient(app), client


def search(api: TestClient, body: dict[str, Any]) -> Any:
    return api.post("/api/v1/live/search", json=body)


def fail(error: Exception) -> Any:
    def respond(call: dict[str, Any]) -> Any:
        raise error

    return respond


def test_search_returns_candidates() -> None:
    api, _ = make_api()

    res = search(api, {"query": "電光石火", "artist": "YOASOBI"})

    assert res.status_code == 200
    body = res.json()
    assert body["found"] is True
    assert body["artist"] == "YOASOBI"
    first = body["candidates"][0]
    assert first["artist"] is None
    assert first["date"] == "2023-06-04"
    assert first["weather"]["kind"] == "actual"
    assert first["weather"]["high_c"] == 27.0


def test_search_accepts_date_only() -> None:
    api, _ = make_api()

    assert search(api, {"date": "2023-06-04"}).status_code == 200


def test_search_rejects_empty_query_and_date_without_calling_gemini() -> None:
    """AC-6"""
    api, client = make_api()

    res = search(api, {"query": "   ", "artist": "YOASOBI"})

    assert res.status_code == 422
    assert calls_of(client) == []


def test_search_returns_502_for_gemini_error() -> None:
    """AC-15"""
    api, _ = make_api(fail(errors.ServerError(500, {"error": {"code": 500}})))

    res = search(api, {"query": "電光石火"})

    assert res.status_code == 502
    assert "ライブ情報の調査に失敗しました" in res.json()["detail"]


def test_search_returns_503_for_quota_error() -> None:
    """AC-15"""
    error = errors.ClientError(429, {"error": {"code": 429, "status": "RESOURCE_EXHAUSTED"}})
    api, _ = make_api(fail(error))

    res = search(api, {"query": "電光石火"})

    assert res.status_code == 503
    assert "クォータ" in res.json()["detail"]


def test_search_returns_504_for_timeout() -> None:
    """AC-15"""

    async def slow(call: dict[str, Any]) -> Any:
        await asyncio.sleep(10)

    api, _ = make_api(slow, live_search_timeout=0.05)

    res = search(api, {"query": "電光石火"})

    assert res.status_code == 504
