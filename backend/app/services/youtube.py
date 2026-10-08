"""YouTube Data API v3 を使って MV のメタ情報を取得する(spec 007)。

入力が URL なら動画情報を、MV 名なら検索結果の候補を返す。
YouTube API のエラーは種類ごとに業務例外へ変換し、ルータが HTTP ステータスに対応付ける。
"""

import html
import logging
import re
from datetime import datetime
from typing import Any
from urllib.parse import parse_qs, urlsplit

import httpx

from app.core.config import Settings, get_settings
from app.schemas.youtube import LookupResponse, VideoCandidate, VideoInfo
from app.services.input_guard import ensure_safe
from app.services.mv_title import parse_title

logger = logging.getLogger(__name__)

API_BASE_URL = "https://www.googleapis.com"
WATCH_URL = "https://www.youtube.com/watch?v={video_id}"

_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
# スキーム無しでも URL とみなす入力(例: "youtu.be/xxxx")
_BARE_URL = re.compile(r"^(?:www\.|m\.|music\.)?(?:youtube\.com|youtu\.be)/", re.IGNORECASE)
_YOUTUBE_HOSTS = {"youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"}
_SHORT_HOSTS = {"youtu.be", "www.youtu.be"}
# /shorts/<ID> のように 2 階層目に動画 ID が入るパス
_ID_IN_PATH = {"shorts", "embed", "live"}
_PLAYLIST_OR_CHANNEL = {"playlist", "channel", "c", "user"}

_QUOTA_REASONS = {
    "quotaExceeded",
    "dailyLimitExceeded",
    "rateLimitExceeded",
    "userRateLimitExceeded",
    "RATE_LIMIT_EXCEEDED",
}
_AUTH_REASONS = {
    "keyInvalid",
    "keyExpired",
    "accessNotConfigured",
    "forbidden",
    "ipRefererBlocked",
    "API_KEY_INVALID",
    "API_KEY_SERVICE_BLOCKED",
    "API_KEY_HTTP_REFERRER_BLOCKED",
    "SERVICE_DISABLED",
}


class YouTubeError(RuntimeError):
    """MV のメタ情報取得に失敗したときの例外の基底。"""


class InvalidVideoUrlError(YouTubeError):
    """YouTube の動画以外の URL が入力された。ルータが 400 に変換する。"""


class VideoNotFoundError(YouTubeError):
    """動画が存在しない・非公開・削除済み。ルータが 404 に変換する。"""


class YouTubeQuotaError(YouTubeError):
    """YouTube API のクォータ超過。時間をおけば回復するため、ルータが 503 に変換する。"""


class YouTubeApiError(YouTubeError):
    """YouTube API の呼び出しに失敗した。ルータが 502 に変換する。"""


class YouTubeAuthError(YouTubeApiError):
    """API キーが無効、または YouTube Data API v3 が有効化されていない。"""


class YouTubeNetworkError(YouTubeApiError):
    """YouTube API に接続できない / 応答がタイムアウトした。"""


def extract_video_id(text: str) -> str | None:
    """入力が YouTube の動画 URL なら動画 ID を返す。URL でなければ None(= MV 名)。

    Raises:
        InvalidVideoUrlError: URL だが YouTube の動画を指していない場合。
    """
    text = text.strip()
    if _BARE_URL.match(text):
        text = f"https://{text}"
    if not re.match(r"^https?://", text, re.IGNORECASE):
        return None

    parts = urlsplit(text)
    host = (parts.hostname or "").lower()
    segments = [s for s in parts.path.split("/") if s]

    candidate: str | None = None
    if host in _SHORT_HOSTS:
        candidate = segments[0] if segments else None
    elif host in _YOUTUBE_HOSTS:
        if segments[:1] == ["watch"]:
            values = parse_qs(parts.query).get("v")
            candidate = values[0] if values else None
        elif len(segments) >= 2 and segments[0] in _ID_IN_PATH:
            candidate = segments[1]
        elif segments and (segments[0] in _PLAYLIST_OR_CHANNEL or segments[0].startswith("@")):
            raise InvalidVideoUrlError(
                "再生リストやチャンネルの URL には対応していません。動画の URL を入力してください。"
            )
    else:
        raise InvalidVideoUrlError("YouTube の URL ではありません。")

    if candidate is None or not _VIDEO_ID.match(candidate):
        raise InvalidVideoUrlError("YouTube の動画の URL として解釈できませんでした。")
    return candidate


def classify_error(status_code: int, payload: Any) -> YouTubeError:
    """YouTube API のエラー応答を業務例外に変換する。

    クォータ超過も HTTP 403 で返るため、認証エラーより先に判定する。
    """
    error = payload.get("error") if isinstance(payload, dict) else None
    error = error if isinstance(error, dict) else {}
    message = str(error.get("message", ""))
    reasons = {
        str(item["reason"])
        for key in ("errors", "details")
        for item in error.get(key) or []
        if isinstance(item, dict) and item.get("reason")
    }

    if status_code == 429 or reasons & _QUOTA_REASONS:
        return YouTubeQuotaError(
            "YouTube API のクォータ(1 日の利用上限)を超えました。時間をおいて再度お試しください。"
        )
    if status_code in (401, 403) or reasons & _AUTH_REASONS or "api key" in message.lower():
        return YouTubeAuthError(
            "YouTube API の認証に失敗しました。YOUTUBE_DATA_API_KEY が正しいか、"
            "YouTube Data API v3 が有効になっているかを確認してください。"
        )
    return YouTubeApiError(f"YouTube API がエラーを返しました(HTTP {status_code}): {message}")


def _thumbnail_url(snippet: dict[str, Any]) -> str:
    thumbnails = snippet.get("thumbnails") or {}
    for size in ("high", "medium", "default"):
        url = (thumbnails.get(size) or {}).get("url")
        if url:
            return str(url)
    return ""


def _published_at(snippet: dict[str, Any]) -> datetime | None:
    try:
        return datetime.fromisoformat(str(snippet["publishedAt"]))
    except (KeyError, ValueError):
        return None


def to_video_info(video_id: str, snippet: dict[str, Any]) -> VideoInfo:
    """videos API の snippet を VideoInfo に詰め替える(タイトルの分解もここで行う)。"""
    title = str(snippet.get("title", ""))
    channel_title = str(snippet.get("channelTitle", ""))
    parsed = parse_title(title, channel_title)
    return VideoInfo(
        video_id=video_id,
        url=WATCH_URL.format(video_id=video_id),
        artist=parsed.artist,
        song_title=parsed.song_title,
        title_parsed=parsed.parsed,
        title=title,
        channel_title=channel_title,
        published_at=_published_at(snippet),
        thumbnail_url=_thumbnail_url(snippet),
        description=str(snippet.get("description", "")),
    )


def to_candidate(video_id: str, snippet: dict[str, Any]) -> VideoCandidate:
    """search API の snippet を VideoCandidate に詰め替える。

    search API はタイトル・チャンネル名を HTML エスケープして返す(`&#39;` など)ため元に戻す。
    """
    return VideoCandidate(
        video_id=video_id,
        url=WATCH_URL.format(video_id=video_id),
        title=html.unescape(str(snippet.get("title", ""))),
        channel_title=html.unescape(str(snippet.get("channelTitle", ""))),
        published_at=_published_at(snippet),
        thumbnail_url=_thumbnail_url(snippet),
    )


class YouTubeService:
    """MV のメタ情報取得のユースケースを担うサービス層。"""

    def __init__(
        self,
        settings: Settings | None = None,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        # transport はテストで httpx.MockTransport に差し替えるためのもの
        self._settings = settings or get_settings()
        self._transport = transport

    async def lookup(self, query: str) -> LookupResponse:
        """URL なら動画情報を、MV 名なら検索結果の候補を返す。"""
        # 不審な言い回しは YouTube を呼ぶ前に断る(spec 037)
        ensure_safe(query, "MV の入力", "youtube/lookup")
        video_id = extract_video_id(query)
        if video_id is not None:
            return LookupResponse(input_type="url", video=await self.get_video(video_id))
        return LookupResponse(input_type="keyword", candidates=await self.search(query.strip()))

    async def get_video(self, video_id: str) -> VideoInfo:
        """動画 ID から動画情報を取得する(1 ユニット)。"""
        payload = await self._get("/youtube/v3/videos", {"part": "snippet", "id": video_id})
        items = payload.get("items") or []
        if not items:
            raise VideoNotFoundError(
                "動画が見つかりませんでした。存在しない・非公開・削除済みの可能性があります。"
            )
        return to_video_info(video_id, items[0].get("snippet") or {})

    async def search(self, keyword: str) -> list[VideoCandidate]:
        """MV 名で動画を検索し、候補を返す(100 ユニット)。0 件なら空の一覧。"""
        params = {
            "part": "snippet",
            "type": "video",
            "q": keyword,
            "maxResults": str(self._settings.youtube_search_max_results),
        }
        if self._settings.youtube_region_code:
            params["regionCode"] = self._settings.youtube_region_code

        payload = await self._get("/youtube/v3/search", params)
        candidates: list[VideoCandidate] = []
        for item in payload.get("items") or []:
            video_id = (item.get("id") or {}).get("videoId")
            if video_id:
                candidates.append(to_candidate(str(video_id), item.get("snippet") or {}))
        return candidates

    async def _get(self, path: str, params: dict[str, str]) -> dict[str, Any]:
        api_key = self._settings.youtube_data_api_key
        if not api_key:
            raise YouTubeApiError(
                "YOUTUBE_DATA_API_KEY が未設定です。backend/.env を確認してください。"
            )

        try:
            async with httpx.AsyncClient(
                base_url=API_BASE_URL,
                timeout=self._settings.youtube_request_timeout,
                transport=self._transport,
            ) as client:
                # キーはヘッダで渡す。クエリに載せると httpx のリクエストログに残るため
                response = await client.get(
                    path, params=params, headers={"X-Goog-Api-Key": api_key}
                )
        except httpx.TimeoutException as exc:
            logger.warning("YouTube API がタイムアウトしました: %s", path)
            raise YouTubeNetworkError(
                "YouTube API の応答がタイムアウトしました。時間をおいて再度お試しください。"
            ) from exc
        except httpx.HTTPError as exc:
            logger.warning("YouTube API に接続できませんでした: %s", path)
            raise YouTubeNetworkError(
                "YouTube API に接続できませんでした。ネットワークを確認してください。"
            ) from exc

        try:
            payload = response.json()
        except ValueError:
            payload = None

        if response.status_code != 200:
            error = classify_error(response.status_code, payload)
            logger.warning(
                "YouTube API がエラーを返しました: %s HTTP %s (%s)",
                path,
                response.status_code,
                type(error).__name__,
            )
            raise error
        if not isinstance(payload, dict):
            raise YouTubeApiError("YouTube API の応答を解釈できませんでした。")
        return payload


def get_youtube_service() -> YouTubeService:
    """FastAPI の Depends 用ファクトリ。テスト時は override して差し替える。"""
    return YouTubeService()
