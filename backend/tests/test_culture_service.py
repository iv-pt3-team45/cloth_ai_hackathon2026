"""カルチャー情報サービスのテスト(Gemini はフェイクのクライアントで差し替える)。"""

import asyncio
from typing import Any

import pytest
from google.genai import errors, types

from app.services import culture
from app.services.culture import (
    MAX_DESCRIPTION_CHARS,
    CultureError,
    CultureQuotaError,
    CultureTimeoutError,
    build_research_prompt,
)
from tests.culture_stub import (
    SENTENCE_1,
    SUGGESTIONS_HTML,
    calls_of,
    default_responder,
    kind,
    make_client,
    make_service,
    make_video,
    research_response,
    structured,
)


def api_error(code: int, status: str = "INTERNAL") -> errors.APIError:
    return errors.ClientError(code, {"error": {"code": code, "message": "x", "status": status}})


# --- プロンプト ------------------------------------------------------------


def test_research_prompt_marks_channel_name_when_title_not_parsed() -> None:
    """AC-7: 分解できなかった動画では、アーティスト名がチャンネル名であることを伝える。"""
    prompt = build_research_prompt(make_video(title_parsed=False, artist="Some Channel"))

    assert "チャンネル名であり、アーティスト名とは限らない: Some Channel" in prompt


def test_research_prompt_truncates_description() -> None:
    prompt = build_research_prompt(make_video(description="あ" * (MAX_DESCRIPTION_CHARS + 50)))

    assert "あ" * MAX_DESCRIPTION_CHARS in prompt
    assert "あ" * (MAX_DESCRIPTION_CHARS + 1) not in prompt


def test_research_prompt_forbids_guessing() -> None:
    """AC-8: 特定できない場合は推測で埋めないよう指示する。"""
    assert "推測で埋めないでください" in build_research_prompt(make_video())


# --- 取得の全体 ------------------------------------------------------------


async def test_research_returns_organized_culture() -> None:
    """AC-3 / AC-4 / AC-5: 項目ごとに整理され、出典と衣装が揃う。"""
    client = make_client()

    result = await make_service(client).research(make_video())

    assert result.identified is True
    assert result.artist == "YOASOBI"
    # 「情報なし」は空として扱う
    assert result.fashion.styles == ["ストリート"]
    assert result.fashion.colors == ["黒", "白"]
    # 範囲外(9)・重複(2)の出典番号は捨てる
    assert result.fashion.source_indices == [2]
    assert result.background.musical_traits == ""
    assert result.background.representative_songs == ["夜に駆ける", "アイドル"]
    assert [s.url for s in result.sources] == ["https://example.com/a", "https://example.org/b"]
    assert result.search_suggestions_html == SUGGESTIONS_HTML
    assert result.mv_outfit.status == "ok"
    item = result.mv_outfit.looks[0].items[0]
    assert (item.category, item.colors, item.style) == ("ワンピース", ["白", "ピンク"], "ガーリー")
    assert result.model == "test-model"


async def test_research_calls_gemini_three_times_with_expected_inputs() -> None:
    client = make_client()
    video = make_video()

    await make_service(client).research(video)

    calls = {kind(c): c for c in calls_of(client)}
    assert set(calls) == {"research", "structure", "outfit"}
    # 1. 調べる: Google 検索あり
    assert calls["research"]["config"].tools[0].google_search is not None
    for name in ("research", "structure", "outfit"):
        assert calls[name]["config"].automatic_function_calling.disable is True
    # 2. 整理する: 出典番号入りの本文を渡し、検索は使わない
    assert f"{SENTENCE_1}[1]" in calls["structure"]["contents"]
    assert not calls["structure"]["config"].tools
    # 3. MV の衣装: YouTube の URL をそのまま、低解像度で渡す
    outfit = calls["outfit"]
    assert outfit["contents"][0].parts[0].file_data.file_uri == video.url
    assert outfit["config"].media_resolution == types.MediaResolution.MEDIA_RESOLUTION_LOW


async def test_research_reports_unidentified_artist() -> None:
    """AC-8: 特定できなければ推測で埋めず、衣装の結果も使わない。"""

    def respond(call: dict[str, Any]) -> Any:
        if kind(call) == "structure":
            return types.GenerateContentResponse(parsed=structured(identified=False))
        return default_responder(call)

    result = await make_service(make_client(respond)).research(make_video())

    assert result.identified is False
    assert result.message == "音楽の動画ではありませんでした。"
    assert result.fashion.styles == []
    assert result.background.summary == ""
    assert result.mv_outfit.status == "skipped"


async def test_research_keeps_web_result_when_video_analysis_fails() -> None:
    """AC-6: 映像を解析できなくても Web の結果は返す。"""

    def respond(call: dict[str, Any]) -> Any:
        if kind(call) == "outfit":
            raise api_error(400, "INVALID_ARGUMENT")
        return default_responder(call)

    result = await make_service(make_client(respond)).research(make_video())

    assert result.identified is True
    assert result.fashion.colors == ["黒", "白"]
    assert result.mv_outfit.status == "unavailable"
    assert "解析できませんでした" in result.mv_outfit.message


async def test_research_treats_unparsed_video_analysis_as_unavailable() -> None:
    def respond(call: dict[str, Any]) -> Any:
        if kind(call) == "outfit":
            return types.GenerateContentResponse(parsed=None)
        return default_responder(call)

    result = await make_service(make_client(respond)).research(make_video())

    assert result.mv_outfit.status == "unavailable"


@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (api_error(429, "RESOURCE_EXHAUSTED"), CultureQuotaError),
        (api_error(500), CultureError),
    ],
)
async def test_research_errors(error: Exception, expected: type[CultureError]) -> None:
    """AC-9: Web の調査の失敗は業務例外になる(クォータは区別する)。"""

    def respond(call: dict[str, Any]) -> Any:
        if kind(call) == "research":
            raise error
        return default_responder(call)

    with pytest.raises(expected) as info:
        await make_service(make_client(respond)).research(make_video())
    assert type(info.value) is expected


async def test_research_fails_when_structure_is_unreadable() -> None:
    def respond(call: dict[str, Any]) -> Any:
        if kind(call) == "structure":
            return types.GenerateContentResponse(parsed=None)
        return default_responder(call)

    with pytest.raises(CultureError, match="解釈"):
        await make_service(make_client(respond)).research(make_video())


async def test_research_fails_when_research_text_is_empty() -> None:
    def respond(call: dict[str, Any]) -> Any:
        if kind(call) == "research":
            return research_response(text="", grounded=False)
        return default_responder(call)

    with pytest.raises(CultureError, match="空"):
        await make_service(make_client(respond)).research(make_video())


async def test_research_times_out_and_cancels_video_analysis() -> None:
    """待ち時間の上限を超えたら 504 用の例外にし、映像の解析も止める。"""
    cancelled: list[str] = []

    async def respond(call: dict[str, Any]) -> Any:
        try:
            await asyncio.sleep(10)
        except asyncio.CancelledError:
            cancelled.append(kind(call))
            raise
        return default_responder(call)

    with pytest.raises(CultureTimeoutError, match="秒以内"):
        await make_service(make_client(respond), culture_timeout=0.05).research(make_video())
    await asyncio.sleep(0)  # 取り消しが反映されるのを待つ
    assert set(cancelled) == {"research", "outfit"}


async def test_research_failure_cancels_video_analysis() -> None:
    """Web の調査が失敗したら、映像の解析は待たずに止める(無駄な課金を避ける)。"""
    cancelled: list[str] = []

    async def respond(call: dict[str, Any]) -> Any:
        if kind(call) == "research":
            # 映像の解析が走り出してから失敗させる
            await asyncio.sleep(0.01)
            raise api_error(500)
        try:
            await asyncio.sleep(10)
        except asyncio.CancelledError:
            cancelled.append(kind(call))
            raise
        return default_responder(call)

    with pytest.raises(CultureError):
        await make_service(make_client(respond)).research(make_video())
    await asyncio.sleep(0)
    assert cancelled == ["outfit"]


async def test_research_reports_client_setup_error(monkeypatch: pytest.MonkeyPatch) -> None:
    def broken_client() -> Any:
        raise RuntimeError("GOOGLE_CLOUD_PROJECT が未設定です。")

    monkeypatch.setattr(culture, "get_media_client", broken_client)

    with pytest.raises(CultureError, match="GOOGLE_CLOUD_PROJECT"):
        await make_service(None).research(make_video())
