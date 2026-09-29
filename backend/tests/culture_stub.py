"""カルチャー情報のテスト用スタブ。Gemini は呼ばない。"""

import inspect
from collections.abc import Callable
from datetime import UTC, datetime
from types import SimpleNamespace
from typing import Any

from google.genai import types

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

SENTENCE_1 = "YOASOBI は 2019 年に結成された音楽ユニットです。"
SENTENCE_2 = "衣装は黒と白を基調にしています。"
RESEARCH_TEXT = SENTENCE_1 + SENTENCE_2
SUGGESTIONS_HTML = "<style>.x{}</style><div class='container'>検索候補</div>"


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
    metadata = types.GroundingMetadata(
        grounding_chunks=[
            types.GroundingChunk(
                web=types.GroundingChunkWeb(
                    uri="https://example.com/a", title="記事A", domain="example.com"
                )
            ),
            types.GroundingChunk(
                web=types.GroundingChunkWeb(
                    uri="https://example.org/b", title="記事B", domain="example.org"
                )
            ),
        ],
        grounding_supports=[
            types.GroundingSupport(
                segment=types.Segment(text=SENTENCE_1), grounding_chunk_indices=[0]
            ),
            types.GroundingSupport(
                segment=types.Segment(text=SENTENCE_2), grounding_chunk_indices=[1, 0]
            ),
        ],
        search_entry_point=types.SearchEntryPoint(rendered_content=SUGGESTIONS_HTML),
        web_search_queries=["YOASOBI ファッション", "YOASOBI 経歴"],
    )
    return types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(role="model", parts=[types.Part(text=text)]),
                grounding_metadata=metadata if grounded else None,
            )
        ]
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
    config: types.GenerateContentConfig = call["config"]
    if config.tools:
        return "research"
    if config.response_schema is StructuredCulture:
        return "structure"
    return "outfit"


Responder = Callable[[dict[str, Any]], Any]


def default_responder(call: dict[str, Any]) -> Any:
    return {
        "research": lambda: research_response(),
        "structure": lambda: types.GenerateContentResponse(parsed=structured()),
        "outfit": lambda: types.GenerateContentResponse(parsed=outfit_analysis()),
    }[kind(call)]()


class FakeModels:
    def __init__(self, respond: Responder) -> None:
        self.calls: list[dict[str, Any]] = []
        self._respond = respond

    async def generate_content(self, *, model: str, contents: Any, config: Any) -> Any:
        call = {"model": model, "contents": contents, "config": config}
        self.calls.append(call)
        result = self._respond(call)
        if inspect.isawaitable(result):
            result = await result
        return result


def make_client(respond: Responder = default_responder) -> Any:
    """`client.aio.models.generate_content` だけを持つフェイク。"""
    return SimpleNamespace(aio=SimpleNamespace(models=FakeModels(respond)))


def make_service(client: Any, **settings: Any) -> CultureService:
    values: dict[str, Any] = {"culture_model": "test-model", "culture_timeout": 5}
    values.update(settings)
    return CultureService(settings=Settings(**values), client=client)


def calls_of(client: Any) -> list[dict[str, Any]]:
    return client.aio.models.calls
