"""YouTube Data API のスタブ(httpx.MockTransport)。実際の API は呼ばない。"""

from collections.abc import Callable
from typing import Any

import httpx

from app.core.config import Settings
from app.services.youtube import YouTubeService

TEST_API_KEY = "test-key"
VIDEO_ID = "abcDEF12345"

Handler = Callable[[httpx.Request], httpx.Response]


def video_snippet(**overrides: Any) -> dict[str, Any]:
    snippet: dict[str, Any] = {
        "publishedAt": "2023-01-01T00:00:00Z",
        "title": "YOASOBI「アイドル」 Official Music Video",
        "description": "概要欄のテキスト",
        "thumbnails": {
            "default": {"url": "https://i.ytimg.com/vi/x/default.jpg"},
            "high": {"url": "https://i.ytimg.com/vi/x/hqdefault.jpg"},
        },
        "channelTitle": "Ayase / YOASOBI",
    }
    snippet.update(overrides)
    return snippet


def videos_body(*snippets: dict[str, Any]) -> dict[str, Any]:
    return {"items": [{"id": VIDEO_ID, "snippet": s} for s in snippets]}


def search_body(count: int) -> dict[str, Any]:
    items = [
        {
            "id": {"kind": "youtube#video", "videoId": f"video{i:06d}"},
            # search API はタイトルを HTML エスケープして返す
            "snippet": video_snippet(title=f"Song &#39;{i}&#39; &amp; MV"),
        }
        for i in range(count)
    ]
    return {"items": items}


def error_body(code: int, reason: str, message: str = "error") -> dict[str, Any]:
    return {"error": {"code": code, "message": message, "errors": [{"reason": reason}]}}


class StubApi:
    """リクエストを記録し、決めておいた応答を返す。"""

    def __init__(self, respond: Callable[[httpx.Request], httpx.Response]) -> None:
        self.requests: list[httpx.Request] = []
        self._respond = respond

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return self._respond(request)


def reply(status_code: int, body: dict[str, Any]) -> StubApi:
    return StubApi(lambda request: httpx.Response(status_code, json=body))


def make_service(api: Handler, api_key: str = TEST_API_KEY, **settings: Any) -> YouTubeService:
    # API キーは明示的に渡す(backend/.env の実キーを使わないため)
    return YouTubeService(
        settings=Settings(youtube_data_api_key=api_key, **settings),
        transport=httpx.MockTransport(api),
    )
