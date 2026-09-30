"""ライブ情報の検索(spec 009)のテスト用スタブ。Gemini は呼ばない。"""

import datetime as dt
from typing import Any

from app.core.config import Settings
from app.services.live import LiveSearchOutput, LiveService, _CandidateOutput, _WeatherOutput
from tests.gemini_stub import Responder, grounded_response, parsed_response, uses_search
from tests.gemini_stub import make_client as _make_client

TODAY = dt.date(2026, 9, 29)
RESEARCH_TEXT = (
    "YOASOBI ARENA TOUR 2023 は 2023年6月4日にさいたまスーパーアリーナで開催されました。"
)


def weather(kind: str = "actual", **overrides: Any) -> _WeatherOutput:
    values: dict[str, Any] = {
        "kind": kind,
        "summary": "晴れ時々曇り",
        "high_c": 27.0,
        "low_c": 18.0,
        "precipitation_chance": 20,
        "source_indices": [1],
    }
    values.update(overrides)
    return _WeatherOutput(**values)


def candidate(**overrides: Any) -> _CandidateOutput:
    values: dict[str, Any] = {
        "artist": "YOASOBI",
        "live_name": 'YOASOBI ARENA TOUR 2023 "電光石火"',
        "venue": "さいたまスーパーアリーナ",
        "location": "埼玉県さいたま市",
        "date": "2023-06-04",
        "weather": weather(),
        "source_indices": [1, 2, 5],
    }
    values.update(overrides)
    return _CandidateOutput(**values)


def output(*candidates: _CandidateOutput, found: bool = True, message: str = "") -> Any:
    return LiveSearchOutput(found=found, message=message, candidates=list(candidates))


def responder(result: Any = None) -> Responder:
    """1. は検索ありの応答、2. は result(既定は候補 1 件)を返す。"""
    structured = result if result is not None else output(candidate())

    def respond(call: dict[str, Any]) -> Any:
        if uses_search(call):
            return grounded_response(RESEARCH_TEXT)
        return parsed_response(structured)

    return respond


def make_client(respond: Responder | None = None) -> Any:
    return _make_client(respond or responder())


def make_service(client: Any, **settings: Any) -> LiveService:
    values: dict[str, Any] = {"live_search_model": "test-model", "live_search_timeout": 5}
    values.update(settings)
    return LiveService(settings=Settings(**values), client=client, today=lambda: TODAY)
