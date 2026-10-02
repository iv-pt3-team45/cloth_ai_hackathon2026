"""会場情報を取得するエージェントツール(F14)。

会場名からGemini APIのGoogle検索グラウンディングで会場情報を調べ、
座席形態(スタンディング/着席/不明)を推定する。

詳細は docs/spec/014-venue-info/design.md を参照。
"""

import logging
from collections.abc import Callable
from enum import StrEnum
from typing import Any, Literal

from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from app.core.config import Settings, get_settings
from app.services.media import get_media_client

logger = logging.getLogger(__name__)


class VenueSearchError(RuntimeError):
    """会場情報の検索(Gemini呼び出し)に失敗したときの例外。"""


class VenueFormat(StrEnum):
    """会場の座席形態。粒度は design.md の決定に合わせ3値とする。"""

    STANDING = "standing"
    SEATED = "seated"
    UNKNOWN = "unknown"


class VenueInfo(BaseModel):
    """会場情報の取得結果。"""

    venue_name: str
    format: VenueFormat = VenueFormat.UNKNOWN
    address: str = Field(
        default="", description="会場の住所(取得できない場合は空文字。F15が利用する)"
    )
    summary: str = Field(default="", description="グラウンディングで得られた説明文(短縮)")
    status: Literal["ok", "error"] = "ok"
    message: str = Field(default="", description="status=error のときの理由")


class _AddressExtraction(BaseModel):
    """住所抽出(2回目のGemini呼び出し)専用の構造化出力スキーマ。"""

    address: str = Field(default="", description="住所。説明文から読み取れない場合は空文字")


_STANDING_KEYWORDS = ("スタンディング", "オールスタンディング", "立見")
_SEATED_KEYWORDS = ("全席指定", "指定席", "着席", "座席指定")


def _classify_format(raw_text: str) -> VenueFormat:
    """会場の説明文からキーワードマッチングで座席形態を判定する。

    外部呼び出しを行わない純粋関数(ユニットテストしやすくするため)。
    スタンディング/着席どちらのキーワードも含む(混在)場合は、
    design.md の決定に従い暫定的に UNKNOWN として扱う。
    """
    has_standing = any(keyword in raw_text for keyword in _STANDING_KEYWORDS)
    has_seated = any(keyword in raw_text for keyword in _SEATED_KEYWORDS)

    if has_standing and has_seated:
        return VenueFormat.UNKNOWN
    if has_standing:
        return VenueFormat.STANDING
    if has_seated:
        return VenueFormat.SEATED
    return VenueFormat.UNKNOWN


def _search_venue(
    venue_name: str,
    settings: Settings | None = None,
    client: genai.Client | None = None,
) -> str:
    """Google検索グラウンディング付きでGeminiに会場情報を説明させる。

    構造化出力は使わない(design.md参照。検索ツールとの併用可否が未検証のため)。
    失敗時は例外を投げる(呼び出し元の get_venue_info でまとめて catch する)。
    """
    settings = settings or get_settings()
    client = client or get_media_client()

    prompt = (
        f"「{venue_name}」という会場について、座席形態(スタンディング/着席/混在)と"
        f"住所(所在地)がわかる範囲で日本語で簡潔に説明してください。分からない場合は分からないと述べてください。"
    )
    try:
        response = client.models.generate_content(
            model=settings.venue_info_model,
            contents=prompt,
            config=types.GenerateContentConfig(
                tools=[types.Tool(google_search=types.GoogleSearch())],
            ),
        )
    except Exception as exc:  # SDK側の例外はまとめて業務例外に変換する
        raise VenueSearchError(str(exc)) from exc

    text = getattr(response, "text", None)
    if not text:
        raise VenueSearchError("Geminiから空の応答が返りました")
    return text


def _extract_address(
    raw_text: str,
    settings: Settings | None = None,
    client: genai.Client | None = None,
) -> str:
    """会場の説明文(_search_venueの結果)から住所だけを抽出する。

    検索ツール(tools)は使わないため、構造化出力(response_schema)を安全に併用できる
    (design.md の技術リスク参照。1回目の検索呼び出しとは別の、tools無しの呼び出し)。
    失敗しても例外を投げず、空文字を返す(住所が取れなくても致命的にしない)。
    """
    prompt = (
        "次の説明文から、会場の住所だけを抽出してください。"
        f"読み取れない場合は空文字にしてください。\n\n{raw_text}"
    )
    try:
        settings = settings or get_settings()
        client = client or get_media_client()
        response = client.models.generate_content(
            model=settings.venue_info_model,
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=_AddressExtraction,
            ),
        )
        parsed = response.parsed
        if isinstance(parsed, _AddressExtraction):
            return parsed.address
        return ""
    except Exception:
        logger.warning(
            "住所の抽出に失敗しました(致命的ではないため空文字で継続します)", exc_info=True
        )
        return ""


def get_venue_info(
    venue_name: str,
    settings: Settings | None = None,
    client: genai.Client | None = None,
) -> VenueInfo:
    """会場名から会場情報を取得する(コアロジック)。

    失敗しても例外を投げず、呼び出し元(エージェント/Orchestrator)を止めない。
    失敗時は format=UNKNOWN / status="error" を返す(requirements.md AC-2)。
    住所抽出(_extract_address)の失敗は致命的にせず、address="" のまま継続する。
    """
    try:
        raw_text = _search_venue(venue_name, settings=settings, client=client)
    except VenueSearchError as exc:
        logger.warning("会場情報の取得に失敗しました(会場名: %s): %s", venue_name, exc)
        return VenueInfo(
            venue_name=venue_name,
            format=VenueFormat.UNKNOWN,
            status="error",
            message=str(exc),
        )

    venue_format = _classify_format(raw_text)
    address = _extract_address(raw_text, settings=settings, client=client)
    return VenueInfo(
        venue_name=venue_name,
        format=venue_format,
        address=address,
        summary=raw_text,
        status="ok",
    )


def build_venue_tools(settings: Settings | None = None) -> list[Callable[..., Any]]:
    """設定を閉じ込めたツール関数を作る(wardrobe.py の build_wardrobe_tools と同じパターン)。"""
    bound = settings or get_settings()

    def get_venue_info_tool(venue_name: str) -> dict[str, Any]:
        """会場名から、会場の座席形態(スタンディング/着席/不明)を調べる。

        「会場は座って見られる?」「スタンディングの会場?」のように、
        コーディネート提案の材料として会場の形態が話題になったときに使う。

        Args:
            venue_name: 調べたい会場の名前(例: "日本武道館")。

        Returns:
            status="ok"の場合、format(standing/seated/unknown)、address(住所、不明な場合は空文字)、
            summary(説明文)。取得に失敗した場合はstatus="error"とmessage(理由)。
            いずれの場合もformatは必ず含まれる(失敗時はunknown)。
        """
        logger.info("[venue_tool] get_venue_info_tool が呼ばれました(venue_name=%r)", venue_name)
        info = get_venue_info(venue_name, settings=bound)
        return info.model_dump(mode="json")

    return [get_venue_info_tool]
