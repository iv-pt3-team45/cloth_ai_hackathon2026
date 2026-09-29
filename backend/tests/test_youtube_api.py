"""MV メタ情報取得 API のテスト(YouTube API は MockTransport で差し替える)。"""

import httpx
from fastapi.testclient import TestClient

from app.main import create_app
from app.services.youtube import get_youtube_service
from tests.youtube_stub import (
    VIDEO_ID,
    StubApi,
    error_body,
    make_service,
    reply,
    search_body,
    video_snippet,
    videos_body,
)


def make_client(api: StubApi) -> TestClient:
    app = create_app()
    service = make_service(api)
    app.dependency_overrides[get_youtube_service] = lambda: service
    return TestClient(app)


def lookup(client: TestClient, query: str) -> httpx.Response:
    return client.post("/api/v1/youtube/lookup", json={"query": query})


def test_lookup_by_url_returns_video() -> None:
    """AC-1"""
    client = make_client(reply(200, videos_body(video_snippet())))

    res = lookup(client, f"https://www.youtube.com/watch?v={VIDEO_ID}")

    assert res.status_code == 200
    body = res.json()
    assert body["input_type"] == "url"
    assert body["candidates"] == []
    video = body["video"]
    assert video["url"] == f"https://www.youtube.com/watch?v={VIDEO_ID}"
    assert (video["artist"], video["song_title"], video["title_parsed"]) == (
        "YOASOBI",
        "アイドル",
        True,
    )
    for key in ("title", "channel_title", "published_at", "thumbnail_url", "description"):
        assert video[key]


def test_lookup_by_keyword_returns_candidates() -> None:
    """AC-3"""
    client = make_client(reply(200, search_body(5)))

    res = lookup(client, "アイドル")

    assert res.status_code == 200
    body = res.json()
    assert body["input_type"] == "keyword"
    assert body["video"] is None
    assert len(body["candidates"]) == 5
    for candidate in body["candidates"]:
        assert candidate["thumbnail_url"] and candidate["title"] and candidate["channel_title"]


def test_selected_candidate_url_returns_video_link() -> None:
    """AC-4: 候補の URL をそのまま送り直すと、その動画のリンクとメタ情報が返る。"""

    def respond(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/search"):
            return httpx.Response(200, json=search_body(1))
        return httpx.Response(200, json=videos_body(video_snippet()))

    client = make_client(StubApi(respond))
    candidate = lookup(client, "アイドル").json()["candidates"][0]

    res = lookup(client, candidate["url"])

    assert res.status_code == 200
    assert res.json()["video"]["url"] == candidate["url"]


def test_lookup_returns_empty_candidates_when_nothing_found() -> None:
    """AC-9: 0 件は 200 の空一覧(表示はフロント)。"""
    res = lookup(make_client(reply(200, {"items": []})), "存在しない曲名")

    assert res.status_code == 200
    assert res.json()["candidates"] == []


def test_lookup_returns_404_for_missing_video() -> None:
    """AC-7"""
    res = lookup(make_client(reply(200, {"items": []})), f"https://youtu.be/{VIDEO_ID}")

    assert res.status_code == 404
    assert "見つかりません" in res.json()["detail"]


def test_lookup_rejects_non_video_url_without_calling_api() -> None:
    """AC-8"""
    api = reply(200, {"items": []})

    res = lookup(make_client(api), "https://www.youtube.com/@YOASOBI")

    assert res.status_code == 400
    assert "チャンネル" in res.json()["detail"]
    assert api.requests == []


def test_lookup_rejects_blank_query_without_calling_api() -> None:
    """AC-8"""
    api = reply(200, {"items": []})

    res = lookup(make_client(api), "   ")

    assert res.status_code == 422
    assert api.requests == []


def test_lookup_returns_503_for_quota_error() -> None:
    """AC-10"""
    res = lookup(make_client(reply(403, error_body(403, "quotaExceeded"))), "アイドル")

    assert res.status_code == 503
    assert "クォータ" in res.json()["detail"]


def test_lookup_returns_502_for_auth_error() -> None:
    """AC-10"""
    res = lookup(make_client(reply(400, error_body(400, "keyInvalid"))), "アイドル")

    assert res.status_code == 502
    assert "認証" in res.json()["detail"]


def test_lookup_returns_502_for_network_error() -> None:
    """AC-10"""

    def fail(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("boom", request=request)

    res = lookup(make_client(StubApi(fail)), "アイドル")

    assert res.status_code == 502
    assert "接続" in res.json()["detail"]
