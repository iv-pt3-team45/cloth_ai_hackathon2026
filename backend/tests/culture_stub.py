"""カルチャー情報(spec 008)のテスト用スタブ。Gemini は呼ばない。"""

from datetime import UTC, datetime
from typing import Any

from app.core.config import Settings
from app.schemas.youtube import VideoInfo
from app.services.cloth_index import ClothItem
from app.services.culture import (
    CultureService,
    StructuredCulture,
    VideoOutfitAnalysis,
    _BackgroundOutput,
    _FashionOutput,
    _LookOutput,
)
from tests.gemini_stub import (
    SUGGESTIONS_HTML,
    Responder,
    calls_of,
    grounded_response,
    parsed_response,
    uses_search,
)
from tests.gemini_stub import make_client as _make_client

__all__ = ["SUGGESTIONS_HTML", "calls_of"]

SENTENCE_1 = "YOASOBI は 2019 年に結成された音楽ユニットです。"
SENTENCE_2 = "衣装は黒と白を基調にしています。"
RESEARCH_TEXT = SENTENCE_1 + SENTENCE_2


def make_video(**overrides: Any) -> VideoInfo:
    values: dict[str, Any] = {
        "video_id": "abcDEF12345",
        "url": "https://www.youtube.com/watch?v=abcDEF12345",
        "artist": "YOASOBI",
        "song_title": "アイドル",
        "title_parsed": True,
        "title": "YOASOBI「アイドル」 Official Music Video",
        "channel_title": "YOASOBI",
        "published_at": datetime(2023, 4, 12, 15, 0, tzinfo=UTC),
        "thumbnail_url": "",
        "description": "概要欄のテキスト",
    }
    values.update(overrides)
    return VideoInfo(**values)


def research_response(text: str = RESEARCH_TEXT, grounded: bool = True) -> Any:
    return grounded_response(
        text,
        supports=[(SENTENCE_1, [0]), (SENTENCE_2, [1, 0])],
        queries=["YOASOBI ファッション", "YOASOBI 経歴"],
        grounded=grounded,
    )


def structured(identified: bool = True, **fashion: Any) -> StructuredCulture:
    fashion_values: dict[str, Any] = {
        "styles": ["ストリート", "情報なし"],
        "colors": ["黒", "白"],
        "items": ["ベレー帽"],
        "worldview": "アニメーションと実写の融合",
        "source_indices": [2, 2, 9],
    }
    fashion_values.update(fashion)
    return StructuredCulture(
        identified=identified,
        artist="YOASOBI" if identified else "",
        message="" if identified else "音楽の動画ではありませんでした。",
        fashion=_FashionOutput(**fashion_values),
        background=_BackgroundOutput(
            summary="小説を音楽にするユニット。",
            history=["2019年 結成"],
            genres=["J-POP"],
            representative_songs=["夜に駆ける", "アイドル"],
            musical_traits="情報なし",
            source_indices=[1],
        ),
    )


def outfit_analysis() -> VideoOutfitAnalysis:
    return VideoOutfitAnalysis(
        looks=[
            _LookOutput(
                label="メインの衣装",
                items=[
                    ClothItem(
                        category="ワンピース",
                        material="不明",
                        shape="ミニ丈",
                        colors=["白", "ピンク"],
                        pattern="無地",
                        style="ガーリー",
                        notes="フリル",
                    )
                ],
            )
        ],
        summary="アイドル風の衣装",
    )


def kind(call: dict[str, Any]) -> str:
    """呼び出しがどの段階(research / structure / outfit)かを設定から判定する。"""
    if uses_search(call):
        return "research"
    if call["config"].response_schema is StructuredCulture:
        return "structure"
    return "outfit"


def default_responder(call: dict[str, Any]) -> Any:
    return {
        "research": lambda: research_response(),
        "structure": lambda: parsed_response(structured()),
        "outfit": lambda: parsed_response(outfit_analysis()),
    }[kind(call)]()


def make_client(respond: Responder = default_responder) -> Any:
    return _make_client(respond)


def make_service(client: Any, **settings: Any) -> CultureService:
    values: dict[str, Any] = {"culture_model": "test-model", "culture_timeout": 5}
    values.update(settings)
    return CultureService(settings=Settings(**values), client=client)
