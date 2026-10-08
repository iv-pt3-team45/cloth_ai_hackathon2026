"""ライブ情報の検索サービスのテスト(Gemini はフェイクのクライアントで差し替える)。"""

import asyncio
import datetime as dt
from typing import Any

import pytest
from google.genai import errors

from app.services import live
from app.services.input_guard import UNTRUSTED_INPUT_RULE
from app.services.live import (
    FORECAST_HORIZON_DAYS,
    LiveSearchError,
    LiveSearchQuotaError,
    LiveSearchTimeoutError,
    build_research_prompt,
    normalize_weather,
    parse_date,
)
from tests.gemini_stub import SUGGESTIONS_HTML, calls_of, uses_search
from tests.live_stub import (
    TODAY,
    candidate,
    make_client,
    make_service,
    output,
    responder,
    weather,
)

# --- プロンプト ------------------------------------------------------------


def test_prompt_limits_to_known_artist() -> None:
    """AC-7: アーティストが分かっていれば、その公演だけを対象にし、名前は調べさせない。"""
    prompt = build_research_prompt("電光石火", None, "YOASOBI", TODAY)

    assert (
        "<user_input>YOASOBI</user_input>(このアーティストの公演だけを対象にしてください)" in prompt
    )
    assert "アーティスト名\n" not in prompt
    assert "1. ライブ名" in prompt


def test_prompt_asks_artist_when_unknown() -> None:
    """AC-8: アーティストが分からなければ、条件から特定させて名前も調べさせる。"""
    prompt = build_research_prompt("", dt.date(2023, 6, 4), None, TODAY)

    assert "指定なし(条件からアーティストも特定してください)" in prompt
    assert "1. アーティスト名" in prompt
    assert "- ライブ情報: 指定なし" in prompt
    assert "- 公演日: 2023-06-04" in prompt


def test_prompt_includes_today_and_forbids_guessing() -> None:
    """AC-10: 今日の日付を渡して実績 / 予報を判断させ、推測で埋めないよう指示する。"""
    prompt = build_research_prompt("電光石火", None, None, TODAY)

    assert "今日の日付: 2026-09-29(日本時間)" in prompt
    assert "予報はまだありません" in prompt
    assert "推測で埋めないでください" in prompt


# --- 天気と日付の整え方 ------------------------------------------------------


@pytest.mark.parametrize(
    ("kind", "date", "expected"),
    [
        ("actual", dt.date(2023, 6, 4), "actual"),
        ("forecast", TODAY + dt.timedelta(days=5), "forecast"),
        # 予報の出ない先の日付の値は根拠が無い
        ("forecast", TODAY + dt.timedelta(days=FORECAST_HORIZON_DAYS + 1), "not_yet"),
        # 未来の日付の「実績」はあり得ない
        ("actual", TODAY + dt.timedelta(days=2), "unknown"),
        ("sunny", dt.date(2023, 6, 4), "unknown"),
        ("NOT_YET", TODAY + dt.timedelta(days=30), "not_yet"),
    ],
)
def test_normalize_weather_kind(kind: str, date: dt.date, expected: str) -> None:
    assert normalize_weather(weather(kind), date, TODAY, 2).kind == expected


def test_normalize_weather_keeps_values_for_actual() -> None:
    """実績は値を残す。降水確率は予報の値なので実績では使わない。"""
    result = normalize_weather(weather("actual"), dt.date(2023, 6, 4), TODAY, 2)

    assert (result.summary, result.high_c, result.low_c, result.precipitation_chance) == (
        "晴れ時々曇り",
        27.0,
        18.0,
        None,
    )


def test_normalize_weather_keeps_chance_for_forecast() -> None:
    result = normalize_weather(weather("forecast"), TODAY + dt.timedelta(days=3), TODAY, 2)

    assert (result.kind, result.precipitation_chance) == ("forecast", 20)


@pytest.mark.parametrize("sources", [[], [9]])
def test_normalize_weather_requires_grounded_sources(sources: list[int]) -> None:
    """AC-10: 出典の無い天気は検索で確認できていないため「不明」にする。"""
    result = normalize_weather(
        weather("actual", source_indices=sources), dt.date(2023, 6, 4), TODAY, 2
    )

    assert (result.kind, result.high_c) == ("unknown", None)


@pytest.mark.parametrize("kind", ["not_yet", "unknown"])
def test_normalize_weather_drops_values_without_basis(kind: str) -> None:
    """AC-10: 予報が無い / 不明なときは値を持たない(推測で埋めない)。"""
    result = normalize_weather(weather(kind), TODAY + dt.timedelta(days=3), TODAY, 2)

    assert (result.summary, result.high_c, result.low_c) == ("", None, None)


def test_normalize_weather_drops_out_of_range_chance() -> None:
    result = normalize_weather(
        weather("forecast", precipitation_chance=150), TODAY + dt.timedelta(days=3), TODAY, 2
    )

    assert result.precipitation_chance is None


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("2023-06-04", dt.date(2023, 6, 4)),
        ("2023/06/04", dt.date(2023, 6, 4)),
        ("不明", None),
        ("", None),
    ],
)
def test_parse_date(value: str, expected: dt.date | None) -> None:
    assert parse_date(value) == expected


# --- 検索の全体 ------------------------------------------------------------


async def test_search_returns_up_to_three_candidates() -> None:
    """AC-5 / AC-9: 最大 3 件。番号は 1 から振り直す。"""
    lives = [candidate(live_name=f"公演{i}") for i in range(4)]
    client = make_client(responder(output(*lives)))

    result = await make_service(client).search("電光石火", None, None)

    assert result.found is True
    assert [c.index for c in result.candidates] == [1, 2, 3]
    assert [c.live_name for c in result.candidates] == ["公演0", "公演1", "公演2"]
    first = result.candidates[0]
    assert (first.venue, first.location, first.date) == (
        "さいたまスーパーアリーナ",
        "埼玉県さいたま市",
        dt.date(2023, 6, 4),
    )
    assert first.weather.kind == "actual"
    # 実在する出典(2 件)だけを残す
    assert first.source_indices == [1, 2]
    assert result.search_suggestions_html == SUGGESTIONS_HTML
    assert len(result.sources) == 2
    assert result.model == "test-model"


async def test_search_wraps_user_input_and_tells_model_not_to_follow_it() -> None:
    """spec 036 AC-5: 利用者の入力は区切り、中の指示に従わないよう指示する。"""
    client = make_client()

    await make_service(client).search("電光石火", None, "YOASOBI")

    research_call = next(c for c in calls_of(client) if uses_search(c))
    assert "- ライブ情報: <user_input>電光石火</user_input>" in research_call["contents"]
    assert UNTRUSTED_INPUT_RULE in research_call["contents"]


async def test_search_omits_artist_when_known() -> None:
    """AC-7: アーティストが分かっていれば候補のアーティスト名は取得しない。"""
    client = make_client()

    result = await make_service(client).search("電光石火", None, "YOASOBI")

    assert result.artist == "YOASOBI"
    assert result.candidates[0].artist is None
    structure_call = next(c for c in calls_of(client) if not uses_search(c))
    assert "指定済み(YOASOBI)" in structure_call["contents"]
    # 関数呼び出しは使わないため、SDK の自動関数呼び出しは無効にする
    assert structure_call["config"].automatic_function_calling.disable is True


async def test_search_returns_artist_when_unknown() -> None:
    """AC-8"""
    result = await make_service(make_client()).search("電光石火", None, "  ")

    assert result.artist == ""
    assert result.candidates[0].artist == "YOASOBI"


async def test_search_drops_empty_candidates_and_reports_not_found() -> None:
    """AC-13: 中身の無い候補だけなら「見つからなかった」扱い。"""
    empty = candidate(live_name="不明", venue="", date="")
    client = make_client(responder(output(empty)))

    result = await make_service(client).search("存在しないライブ", None, None)

    assert result.found is False
    assert result.candidates == []
    assert result.message == "該当するライブが見つかりませんでした。"


async def test_search_reports_not_found_message() -> None:
    client = make_client(responder(output(found=False, message="条件に合う公演がありません。")))

    result = await make_service(client).search("", dt.date(2020, 1, 1), "YOASOBI")

    assert (result.found, result.message) == (False, "条件に合う公演がありません。")
    # 検索は実行されているため、検索候補は返す
    assert result.search_suggestions_html == SUGGESTIONS_HTML


def api_error(code: int, status: str = "INTERNAL") -> errors.APIError:
    return errors.ClientError(code, {"error": {"code": code, "message": "x", "status": status}})


@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (api_error(429, "RESOURCE_EXHAUSTED"), LiveSearchQuotaError),
        (api_error(500), LiveSearchError),
    ],
)
async def test_search_errors(error: Exception, expected: type[LiveSearchError]) -> None:
    """AC-15"""

    def respond(call: dict[str, Any]) -> Any:
        raise error

    with pytest.raises(expected) as info:
        await make_service(make_client(respond)).search("電光石火", None, None)
    assert type(info.value) is expected


async def test_search_fails_when_structure_is_unreadable() -> None:
    def respond(call: dict[str, Any]) -> Any:
        if uses_search(call):
            return responder()(call)
        return live.types.GenerateContentResponse(parsed=None)

    with pytest.raises(LiveSearchError, match="解釈"):
        await make_service(make_client(respond)).search("電光石火", None, None)


async def test_search_times_out() -> None:
    async def respond(call: dict[str, Any]) -> Any:
        await asyncio.sleep(10)

    with pytest.raises(LiveSearchTimeoutError, match="秒以内"):
        await make_service(make_client(respond), live_search_timeout=0.05).search(
            "電光石火", None, None
        )


async def test_search_reports_client_setup_error(monkeypatch: pytest.MonkeyPatch) -> None:
    def broken_client() -> Any:
        raise RuntimeError("GOOGLE_CLOUD_PROJECT が未設定です。")

    monkeypatch.setattr(live, "get_media_client", broken_client)

    with pytest.raises(LiveSearchError, match="GOOGLE_CLOUD_PROJECT"):
        await make_service(None).search("電光石火", None, None)
