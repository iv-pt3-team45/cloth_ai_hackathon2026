"""会場の形態を調べる API のテスト(spec 014。F14 はフェイクで差し替える)。"""

from typing import Any

from fastapi.testclient import TestClient

from app.main import create_app
from app.services.venue import VenueFormat, VenueInfo, VenueLookup, get_venue_lookup


def make_api(lookup: VenueLookup) -> TestClient:
    app = create_app()
    app.dependency_overrides[get_venue_lookup] = lambda: lookup
    return TestClient(app)


def test_lookup_returns_format_and_passes_hints() -> None:
    received: dict[str, Any] = {}

    def standing(venue_name: str, **kwargs: Any) -> VenueInfo:
        received.update(venue_name=venue_name, **kwargs)
        return VenueInfo(venue_name=venue_name, format=VenueFormat.STANDING, summary="説明文")

    res = make_api(standing).post(
        "/api/v1/venue/lookup",
        json={
            "venue": " さいたまスーパーアリーナ ",
            "location": "埼玉県さいたま市",
            "live_name": "ARENA TOUR",
            "date": "2023-06-04",
        },
    )

    assert res.status_code == 200
    assert res.json() == {
        "venue_name": "さいたまスーパーアリーナ",
        "format": "standing",
        "status": "ok",
        "message": "",
    }
    # 説明文(グラウンディング結果)は返さない
    assert "summary" not in res.json()
    assert received["venue_name"] == "さいたまスーパーアリーナ"
    assert received["location"] == "埼玉県さいたま市"
    assert received["live_name"] == "ARENA TOUR"
    assert received["live_date"] == "2023-06-04"


def test_lookup_accepts_venue_only() -> None:
    received: dict[str, Any] = {}

    def mixed(venue_name: str, **kwargs: Any) -> VenueInfo:
        received.update(kwargs)
        return VenueInfo(venue_name=venue_name, format=VenueFormat.MIXED)

    res = make_api(mixed).post("/api/v1/venue/lookup", json={"venue": "Zepp Haneda"})

    assert res.status_code == 200
    assert res.json()["format"] == "mixed"
    assert received["location"] == ""
    assert received["live_date"] == ""


def test_lookup_failure_is_200_unknown() -> None:
    """F14 は失敗しても例外を投げないので、API も 200 で unknown を返す。"""

    def failed(venue_name: str, **_: Any) -> VenueInfo:
        return VenueInfo(venue_name=venue_name, status="error", message="APIエラー")

    res = make_api(failed).post("/api/v1/venue/lookup", json={"venue": "日本武道館"})

    assert res.status_code == 200
    body = res.json()
    assert body["format"] == "unknown"
    assert body["status"] == "error"
    assert body["message"] == "APIエラー"


def test_lookup_rejects_empty_venue_without_calling_f14() -> None:
    called: list[str] = []

    def record(venue_name: str, **_: Any) -> VenueInfo:
        called.append(venue_name)
        return VenueInfo(venue_name=venue_name)

    api = make_api(record)

    assert api.post("/api/v1/venue/lookup", json={"venue": "   "}).status_code == 422
    assert api.post("/api/v1/venue/lookup", json={}).status_code == 422
    assert called == []
