"""会場情報を取得するエージェントツール(F14)。

会場名(と、分かれば所在地・ライブ名・公演日)からGemini APIのGoogle検索グラウンディングで
会場情報を調べ、座席形態(スタンディング/着席/不明)を推定する。

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
    summary: str = Field(default="", description="グラウンディングで得られた説明文(短縮)")
    status: Literal["ok", "error"] = "ok"
    message: str = Field(default="", description="status=error のときの理由")


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


def _build_search_prompt(
    venue_name: str,
    location: str = "",
    live_name: str = "",
    live_date: str = "",
) -> str:
    """会場検索のプロンプトを組み立てる(外部呼び出しなしの純粋関数)。

    所在地・ライブ名・公演日は任意の手がかり。
    - 所在地: 同名・複数拠点の会場(例: 市民ホール、Zepp)の取り違えを防ぐ。
    - ライブ名・公演日: 座席形態は会場よりも公演ごとに決まることが多いため、
      その公演での形態を優先して調べさせる。
    """
    venue = f"「{venue_name}」" + (f"({location})" if location else "")
    event_parts = [part for part in (live_name, live_date) if part]
    if event_parts:
        event = "、".join(event_parts)
        return (
            f"{venue}で行われるライブ({event})の座席形態"
            "(スタンディング/着席/混在)を、わかる範囲で日本語で簡潔に説明してください。"
            "その公演の形態が分からない場合は、会場の一般的な形態を述べてください。"
            "分からない場合は分からないと述べてください。"
        )
    return (
        f"{venue}という会場の座席形態(スタンディング/着席/混在)を、"
        "わかる範囲で日本語で簡潔に説明してください。分からない場合は分からないと述べてください。"
    )


def _search_venue(
    venue_name: str,
    settings: Settings | None = None,
    client: genai.Client | None = None,
    *,
    location: str = "",
    live_name: str = "",
    live_date: str = "",
) -> str:
    """Google検索グラウンディング付きでGeminiに会場情報を説明させる。

    構造化出力は使わない(検索ツールとの併用可否が未検証のため。design.md参照)。
    失敗時は例外を投げる(呼び出し元の get_venue_info でまとめて catch する)。
    """
    settings = settings or get_settings()
    client = client or get_media_client()

    prompt = _build_search_prompt(venue_name, location, live_name, live_date)
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


def get_venue_info(
    venue_name: str,
    settings: Settings | None = None,
    client: genai.Client | None = None,
    *,
    location: str = "",
    live_name: str = "",
    live_date: str = "",
) -> VenueInfo:
    """会場名から会場情報を取得する(コアロジック)。

    location / live_name / live_date は任意の手がかり(F09のライブ情報検索の結果など)。
    渡すと検索の精度が上がる。未指定でも動く。live_date は "YYYY-MM-DD" 形式の文字列。

    失敗しても例外を投げず、呼び出し元(エージェント/Orchestrator)を止めない。
    失敗時は format=UNKNOWN / status="error" を返す(requirements.md AC-2)。
    """
    try:
        raw_text = _search_venue(
            venue_name,
            settings=settings,
            client=client,
            location=location,
            live_name=live_name,
            live_date=live_date,
        )
    except VenueSearchError as exc:
        logger.warning("会場情報の取得に失敗しました(会場名: %s): %s", venue_name, exc)
        return VenueInfo(
            venue_name=venue_name,
            format=VenueFormat.UNKNOWN,
            status="error",
            message=str(exc),
        )

    return VenueInfo(
        venue_name=venue_name,
        format=_classify_format(raw_text),
        summary=raw_text,
        status="ok",
    )


def build_venue_tools(settings: Settings | None = None) -> list[Callable[..., Any]]:
    """設定を閉じ込めたツール関数を作る(wardrobe.py の build_wardrobe_tools と同じパターン)。"""
    bound = settings or get_settings()

    def get_venue_info_tool(
        venue_name: str,
        location: str = "",
        live_name: str = "",
        live_date: str = "",
    ) -> dict[str, Any]:
        """会場名から、会場の座席形態(スタンディング/着席/不明)を調べる。

        「会場は座って見られる?」「スタンディングの会場?」のように、
        コーディネート提案の材料として会場の形態が話題になったときに使う。

        Args:
            venue_name: 調べたい会場の名前(例: "日本武道館")。
            location: 会場の所在地(都道府県・市区町村)。分かるときだけ渡す。
            live_name: ライブ名・ツアー名。分かるときだけ渡す。
            live_date: 公演日(YYYY-MM-DD)。分かるときだけ渡す。

        Returns:
            status="ok"の場合、format(standing/seated/unknown)とsummary(説明文)。
            取得に失敗した場合はstatus="error"とmessage(理由)。
            いずれの場合もformatは必ず含まれる(失敗時はunknown)。
        """
        logger.info(
            "[venue_tool] get_venue_info_tool が呼ばれました(venue_name=%r, location=%r)",
            venue_name,
            location,
        )
        info = get_venue_info(
            venue_name,
            settings=bound,
            location=location,
            live_name=live_name,
            live_date=live_date,
        )
        return info.model_dump(mode="json")

    return [get_venue_info_tool]
