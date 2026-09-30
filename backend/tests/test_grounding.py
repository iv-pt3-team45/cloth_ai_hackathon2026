"""グラウンディングの共通処理のテスト(Gemini は呼ばない)。"""

from typing import Any

import pytest
from google.genai import errors, types

from app.services.grounding import (
    clean_list,
    clean_text,
    extract_research,
    grounded_research,
    insert_citations,
    is_quota_error,
    valid_indices,
)
from tests.culture_stub import RESEARCH_TEXT, SENTENCE_1, SENTENCE_2, research_response
from tests.gemini_stub import SUGGESTIONS_HTML, calls_of, make_client


def test_insert_citations_places_markers_after_japanese_segments() -> None:
    """日本語の本文でも、根拠の文の直後に番号が入る。"""
    supports = [
        types.GroundingSupport(segment=types.Segment(text=SENTENCE_1), grounding_chunk_indices=[0]),
        types.GroundingSupport(
            segment=types.Segment(text=SENTENCE_2), grounding_chunk_indices=[1, 0]
        ),
    ]

    text = insert_citations(RESEARCH_TEXT, supports, {0: 1, 1: 2})

    assert text == f"{SENTENCE_1}[1]{SENTENCE_2}[1][2]"


def test_insert_citations_skips_unknown_segments_and_chunks() -> None:
    supports = [
        types.GroundingSupport(
            segment=types.Segment(text="本文に無い文"), grounding_chunk_indices=[0]
        ),
        types.GroundingSupport(segment=types.Segment(text=SENTENCE_1), grounding_chunk_indices=[7]),
        types.GroundingSupport(segment=None, grounding_chunk_indices=[0]),
    ]

    assert insert_citations(RESEARCH_TEXT, supports, {0: 1}) == RESEARCH_TEXT


def test_extract_research_collects_sources_and_suggestions() -> None:
    research = extract_research(research_response())

    assert [(s.index, s.title, s.url, s.domain) for s in research.sources] == [
        (1, "記事A", "https://example.com/a", "example.com"),
        (2, "記事B", "https://example.org/b", "example.org"),
    ]
    assert research.text == f"{SENTENCE_1}[1]{SENTENCE_2}[1][2]"
    assert research.search_suggestions_html == SUGGESTIONS_HTML
    assert research.web_search_queries == ["YOASOBI ファッション", "YOASOBI 経歴"]


def test_extract_research_numbers_only_web_chunks() -> None:
    response = research_response()
    metadata = response.candidates[0].grounding_metadata
    metadata.grounding_chunks.insert(0, types.GroundingChunk(web=None))
    metadata.grounding_supports[0].grounding_chunk_indices = [1]

    research = extract_research(response)

    assert [s.index for s in research.sources] == [1, 2]
    assert research.text.startswith(f"{SENTENCE_1}[1]")


def test_extract_research_without_grounding() -> None:
    research = extract_research(research_response(grounded=False))

    assert research.text == RESEARCH_TEXT
    assert research.sources == []
    assert research.search_suggestions_html == ""


async def test_grounded_research_uses_google_search_without_afc() -> None:
    client = make_client(lambda call: research_response())

    research = await grounded_research(client, "test-model", "調べて")

    call = calls_of(client)[0]
    assert call["model"] == "test-model"
    assert call["contents"] == "調べて"
    assert call["config"].tools[0].google_search is not None
    assert call["config"].automatic_function_calling.disable is True
    assert len(research.sources) == 2


def test_valid_indices_drops_out_of_range_and_duplicates() -> None:
    assert valid_indices([2, 2, 9, 0, 1], 2) == [1, 2]


def test_clean_helpers_drop_no_info() -> None:
    assert clean_list([" 黒 ", "情報なし", "不明", ""]) == ["黒"]
    assert clean_text(" 情報なし ") == ""
    assert clean_text(" 晴れ ") == "晴れ"


@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (errors.ClientError(429, {"error": {"code": 429}}), True),
        (errors.ClientError(400, {"error": {"code": 400, "status": "RESOURCE_EXHAUSTED"}}), True),
        (errors.ServerError(500, {"error": {"code": 500}}), False),
        (RuntimeError("x"), False),
    ],
)
def test_is_quota_error(error: Any, expected: bool) -> None:
    assert is_quota_error(error) is expected
