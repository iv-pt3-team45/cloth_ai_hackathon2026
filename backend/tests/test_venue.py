"""venue.py の単体テスト(外部通信は行わない)。"""

from app.services.venue import VenueFormat, _build_search_prompt, _classify_format


def test_classify_format_standing() -> None:
    assert _classify_format("この会場はオールスタンディング形式です。") == VenueFormat.STANDING


def test_classify_format_seated() -> None:
    assert _classify_format("全席指定のホールです。") == VenueFormat.SEATED


def test_classify_format_unknown_when_no_keyword() -> None:
    assert _classify_format("収容人数は5000人規模の会場です。") == VenueFormat.UNKNOWN


def test_classify_format_unknown_when_mixed() -> None:
    assert (
        _classify_format("1階はスタンディング、2階は全席指定のホールです。") == VenueFormat.UNKNOWN
    )


def test_build_search_prompt_venue_only() -> None:
    prompt = _build_search_prompt("日本武道館")
    assert "「日本武道館」" in prompt
    assert "ライブ" not in prompt


def test_build_search_prompt_includes_location() -> None:
    prompt = _build_search_prompt("市民ホール", location="愛知県名古屋市")
    assert "「市民ホール」(愛知県名古屋市)" in prompt


def test_build_search_prompt_includes_live_name_and_date() -> None:
    prompt = _build_search_prompt("日本武道館", live_name="Hoge Tour 2026", live_date="2026-12-24")
    assert "Hoge Tour 2026" in prompt
    assert "2026-12-24" in prompt


def test_build_search_prompt_does_not_ask_for_address() -> None:
    assert "住所" not in _build_search_prompt("日本武道館", location="東京都千代田区")


def test_get_venue_info_ok(monkeypatch) -> None:
    from app.services import venue

    monkeypatch.setattr(
        venue,
        "_search_venue",
        lambda venue_name, settings=None, client=None, **hints: "全席指定のホールです。",
    )
    result = venue.get_venue_info("テスト会場")
    assert result.status == "ok"
    assert result.format == venue.VenueFormat.SEATED
    assert result.summary == "全席指定のホールです。"


def test_get_venue_info_passes_hints_to_search(monkeypatch) -> None:
    from app.services import venue

    received: dict[str, str] = {}

    def _fake_search(venue_name, settings=None, client=None, **hints):
        received.update(hints)
        return "オールスタンディングです。"

    monkeypatch.setattr(venue, "_search_venue", _fake_search)
    result = venue.get_venue_info(
        "テスト会場", location="東京都", live_name="テストツアー", live_date="2026-12-24"
    )
    assert result.format == venue.VenueFormat.STANDING
    assert received == {
        "location": "東京都",
        "live_name": "テストツアー",
        "live_date": "2026-12-24",
    }


def test_get_venue_info_error_when_search_fails(monkeypatch) -> None:
    from app.services import venue

    def _raise(venue_name, settings=None, client=None, **hints):
        raise venue.VenueSearchError("APIエラー")

    monkeypatch.setattr(venue, "_search_venue", _raise)
    result = venue.get_venue_info("テスト会場")
    assert result.status == "error"
    assert result.format == venue.VenueFormat.UNKNOWN
    assert result.message == "APIエラー"


def test_search_venue_sends_prompt_with_hints() -> None:
    from unittest.mock import MagicMock

    from app.services import venue

    mock_response = MagicMock()
    mock_response.text = "全席指定です。"
    mock_client = MagicMock()
    mock_client.models.generate_content.return_value = mock_response

    text = venue._search_venue(
        "市民ホール", client=mock_client, location="愛知県名古屋市", live_name="テストツアー"
    )
    assert text == "全席指定です。"
    contents = mock_client.models.generate_content.call_args.kwargs["contents"]
    assert "愛知県名古屋市" in contents
    assert "テストツアー" in contents
