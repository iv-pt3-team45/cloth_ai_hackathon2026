"""YouTube サービスのテスト(YouTube API は MockTransport で差し替える)。"""

from datetime import UTC, datetime

import httpx
import pytest

from app.services.youtube import (
    InvalidVideoUrlError,
    VideoNotFoundError,
    YouTubeApiError,
    YouTubeAuthError,
    YouTubeNetworkError,
    YouTubeQuotaError,
    extract_video_id,
)
from tests.youtube_stub import (
    TEST_API_KEY,
    VIDEO_ID,
    StubApi,
    error_body,
    make_service,
    reply,
    search_body,
    video_snippet,
    videos_body,
)

# --- URL の解析 -------------------------------------------------------------


@pytest.mark.parametrize(
    "url",
    [
        f"https://www.youtube.com/watch?v={VIDEO_ID}",
        f"https://youtube.com/watch?v={VIDEO_ID}&t=42s",
        f"https://www.youtube.com/watch?v={VIDEO_ID}&list=PLabc&index=2",
        f"https://www.youtube.com/watch?app=desktop&v={VIDEO_ID}",
        f"https://m.youtube.com/watch?v={VIDEO_ID}",
        f"https://music.youtube.com/watch?v={VIDEO_ID}&si=abc",
        f"https://youtu.be/{VIDEO_ID}",
        f"https://youtu.be/{VIDEO_ID}?si=abc&t=10",
        f"https://www.youtube.com/shorts/{VIDEO_ID}",
        f"https://www.youtube.com/embed/{VIDEO_ID}?start=5",
        f"https://www.youtube.com/live/{VIDEO_ID}",
        f"youtu.be/{VIDEO_ID}",
        f"www.youtube.com/watch?v={VIDEO_ID}",
        f"  https://youtu.be/{VIDEO_ID}  ",
        f"HTTPS://WWW.YOUTUBE.COM/watch?v={VIDEO_ID}",
    ],
)
def test_extract_video_id_accepts_video_urls(url: str) -> None:
    """AC-2: 形式や余分なパラメータが違っても同じ動画 ID になる。"""
    assert extract_video_id(url) == VIDEO_ID


@pytest.mark.parametrize(
    "url",
    [
        "https://www.youtube.com/playlist?list=PLabc",
        "https://www.youtube.com/@YOASOBI",
        "https://www.youtube.com/channel/UCabc",
        "https://www.youtube.com/c/abc",
        f"https://example.com/watch?v={VIDEO_ID}",
        "https://www.youtube.com/watch",
        "https://www.youtube.com/watch?v=short",
        "https://youtu.be/",
        "https://www.youtube.com/",
    ],
)
def test_extract_video_id_rejects_non_video_urls(url: str) -> None:
    """AC-8: YouTube の動画以外の URL は入力エラー。"""
    with pytest.raises(InvalidVideoUrlError):
        extract_video_id(url)


@pytest.mark.parametrize(
    "text", ["YOASOBI アイドル", "夜に駆ける", "Official髭男dism - Pretender", "youtube.comのMV"]
)
def test_extract_video_id_treats_other_text_as_keyword(text: str) -> None:
    assert extract_video_id(text) is None


# --- 動画情報の取得 ---------------------------------------------------------


async def test_get_video_returns_metadata() -> None:
    """AC-1: メタ情報が揃い、タイトルが分解される。"""
    api = reply(200, videos_body(video_snippet()))

    video = await make_service(api).get_video(VIDEO_ID)

    assert video.video_id == VIDEO_ID
    assert video.url == f"https://www.youtube.com/watch?v={VIDEO_ID}"
    assert (video.artist, video.song_title, video.title_parsed) == ("YOASOBI", "アイドル", True)
    assert video.title == "YOASOBI「アイドル」 Official Music Video"
    assert video.channel_title == "Ayase / YOASOBI"
    assert video.published_at == datetime(2023, 1, 1, tzinfo=UTC)
    assert video.thumbnail_url == "https://i.ytimg.com/vi/x/hqdefault.jpg"
    assert video.description == "概要欄のテキスト"


async def test_get_video_sends_key_in_header_not_query() -> None:
    """キーをクエリに載せない(httpx のリクエストログに残るため)。"""
    api = reply(200, videos_body(video_snippet()))

    await make_service(api).get_video(VIDEO_ID)

    request = api.requests[0]
    assert request.url.path == "/youtube/v3/videos"
    assert request.url.params["id"] == VIDEO_ID
    assert request.headers["X-Goog-Api-Key"] == TEST_API_KEY
    assert "key" not in request.url.params
    assert TEST_API_KEY not in str(request.url)


async def test_get_video_keeps_raw_values_when_title_is_not_parsed() -> None:
    """AC-6: 分解できなければチャンネル名・動画タイトルのまま。"""
    api = reply(200, videos_body(video_snippet(title="Lemon", channelTitle="米津玄師")))

    video = await make_service(api).get_video(VIDEO_ID)

    assert (video.artist, video.song_title, video.title_parsed) == ("米津玄師", "Lemon", False)


async def test_get_video_raises_not_found_for_empty_items() -> None:
    """AC-7: 存在しない・非公開・削除済みの動画は items が空で返る。"""
    api = reply(200, {"items": []})

    with pytest.raises(VideoNotFoundError):
        await make_service(api).get_video(VIDEO_ID)


# --- 検索 -------------------------------------------------------------------


async def test_search_returns_candidates() -> None:
    """AC-3: 候補の一覧が返り、HTML エスケープが戻される。"""
    api = reply(200, search_body(5))

    candidates = await make_service(api).search("アイドル")

    assert len(candidates) == 5
    first = candidates[0]
    assert first.video_id == "video000000"
    assert first.url == "https://www.youtube.com/watch?v=video000000"
    assert first.title == "Song '0' & MV"
    assert first.channel_title == "Ayase / YOASOBI"
    assert first.thumbnail_url == "https://i.ytimg.com/vi/x/hqdefault.jpg"

    params = api.requests[0].url.params
    assert api.requests[0].url.path == "/youtube/v3/search"
    assert (params["q"], params["type"], params["maxResults"]) == ("アイドル", "video", "5")
    assert params["regionCode"] == "JP"


async def test_search_uses_settings() -> None:
    api = reply(200, search_body(0))

    await make_service(api, youtube_search_max_results=3, youtube_region_code="").search("x")

    params = api.requests[0].url.params
    assert params["maxResults"] == "3"
    assert "regionCode" not in params


async def test_search_skips_items_without_video_id() -> None:
    body = search_body(1)
    body["items"].append({"id": {"kind": "youtube#channel", "channelId": "UCabc"}})
    api = reply(200, body)

    candidates = await make_service(api).search("x")

    assert [c.video_id for c in candidates] == ["video000000"]


async def test_search_returns_empty_list_when_nothing_found() -> None:
    """AC-9: 0 件は例外ではなく空の一覧。"""
    assert await make_service(reply(200, {"items": []})).search("x") == []


# --- 入力の振り分け ---------------------------------------------------------


async def test_lookup_url_returns_video() -> None:
    result = await make_service(reply(200, videos_body(video_snippet()))).lookup(
        f"https://youtu.be/{VIDEO_ID}"
    )

    assert result.input_type == "url"
    assert result.video is not None
    assert result.candidates == []


async def test_lookup_keyword_returns_candidates() -> None:
    api = reply(200, search_body(2))

    result = await make_service(api).lookup("  アイドル  ")

    assert result.input_type == "keyword"
    assert result.video is None
    assert len(result.candidates) == 2
    assert api.requests[0].url.params["q"] == "アイドル"


async def test_lookup_invalid_url_does_not_call_api() -> None:
    """AC-8: 入力エラーのときは YouTube API を呼ばない。"""
    api = reply(200, {"items": []})

    with pytest.raises(InvalidVideoUrlError):
        await make_service(api).lookup("https://www.youtube.com/playlist?list=PLabc")
    assert api.requests == []


# --- エラーの正規化 ---------------------------------------------------------


@pytest.mark.parametrize(
    ("status_code", "body"),
    [
        (403, error_body(403, "quotaExceeded")),
        (403, error_body(403, "dailyLimitExceeded")),
        (429, {}),
    ],
)
async def test_quota_errors(status_code: int, body: dict[str, object]) -> None:
    """AC-10: クォータ超過(HTTP 403 でも認証エラーと区別する)。"""
    with pytest.raises(YouTubeQuotaError, match="クォータ"):
        await make_service(reply(status_code, body)).get_video(VIDEO_ID)


@pytest.mark.parametrize(
    ("status_code", "body"),
    [
        (400, error_body(400, "badRequest", "API key not valid. Please pass a valid API key.")),
        (400, error_body(400, "keyInvalid")),
        (403, error_body(403, "accessNotConfigured")),
        (
            403,
            {"error": {"code": 403, "message": "x", "details": [{"reason": "SERVICE_DISABLED"}]}},
        ),
        (401, {}),
    ],
)
async def test_auth_errors(status_code: int, body: dict[str, object]) -> None:
    """AC-10: 認証エラー。メッセージにキーを含めない。"""
    with pytest.raises(YouTubeAuthError, match="認証") as info:
        await make_service(reply(status_code, body)).get_video(VIDEO_ID)
    assert TEST_API_KEY not in str(info.value)


@pytest.mark.parametrize(
    ("error", "expected"),
    [(httpx.ConnectError, "接続"), (httpx.ReadTimeout, "タイムアウト")],
)
async def test_network_errors(error: type[httpx.TransportError], expected: str) -> None:
    """AC-10: 通信エラー。"""

    def fail(request: httpx.Request) -> httpx.Response:
        raise error("boom", request=request)

    with pytest.raises(YouTubeNetworkError, match=expected):
        await make_service(StubApi(fail)).get_video(VIDEO_ID)


async def test_other_api_errors() -> None:
    with pytest.raises(YouTubeApiError, match="HTTP 500") as info:
        await make_service(reply(500, error_body(500, "backendError", "boom"))).get_video(VIDEO_ID)
    assert not isinstance(info.value, (YouTubeAuthError, YouTubeNetworkError))


async def test_unreadable_response() -> None:
    api = StubApi(lambda request: httpx.Response(200, text="<html>"))

    with pytest.raises(YouTubeApiError, match="解釈"):
        await make_service(api).get_video(VIDEO_ID)


async def test_missing_api_key_does_not_call_api() -> None:
    api = reply(200, videos_body(video_snippet()))

    with pytest.raises(YouTubeApiError, match="YOUTUBE_DATA_API_KEY"):
        await make_service(api, api_key="").get_video(VIDEO_ID)
    assert api.requests == []
