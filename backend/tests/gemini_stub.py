"""Gemini のフェイククライアントと、グラウンディング応答の組み立て(spec 008 / 009 のテスト用)。"""

import inspect
from collections.abc import Callable, Sequence
from types import SimpleNamespace
from typing import Any

from google.genai import types

SUGGESTIONS_HTML = "<style>.x{}</style><div class='container'>検索候補</div>"

# (uri, title, domain)
DEFAULT_CHUNKS = [
    ("https://example.com/a", "記事A", "example.com"),
    ("https://example.org/b", "記事B", "example.org"),
]


def grounded_response(
    text: str,
    *,
    chunks: Sequence[tuple[str, str, str]] = DEFAULT_CHUNKS,
    supports: Sequence[tuple[str, list[int]]] = (),
    queries: Sequence[str] = ("検索クエリ",),
    grounded: bool = True,
) -> Any:
    """検索ありの呼び出しの応答。supports は (根拠の文, grounding_chunks の添字) の並び。"""
    metadata = types.GroundingMetadata(
        grounding_chunks=[
            types.GroundingChunk(web=types.GroundingChunkWeb(uri=uri, title=title, domain=domain))
            for uri, title, domain in chunks
        ],
        grounding_supports=[
            types.GroundingSupport(segment=types.Segment(text=segment), grounding_chunk_indices=idx)
            for segment, idx in supports
        ],
        search_entry_point=types.SearchEntryPoint(rendered_content=SUGGESTIONS_HTML),
        web_search_queries=list(queries),
    )
    return types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(role="model", parts=[types.Part(text=text)]),
                grounding_metadata=metadata if grounded else None,
            )
        ]
    )


def parsed_response(parsed: Any) -> Any:
    """構造化出力(response_schema)の応答。"""
    return types.GenerateContentResponse(parsed=parsed)


def uses_search(call: dict[str, Any]) -> bool:
    """検索ありの呼び出しか。"""
    return bool(call["config"].tools)


Responder = Callable[[dict[str, Any]], Any]


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


def make_client(respond: Responder) -> Any:
    """`client.aio.models.generate_content` だけを持つフェイク。"""
    return SimpleNamespace(aio=SimpleNamespace(models=FakeModels(respond)))


def calls_of(client: Any) -> list[dict[str, Any]]:
    return client.aio.models.calls
