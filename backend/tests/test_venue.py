"""venue.py の単体テスト(外部通信は行わない)。"""

from app.services.venue import VenueFormat, _classify_format


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


def test_get_venue_info_ok(monkeypatch) -> None:
    from app.services import venue

    monkeypatch.setattr(
        venue,
        "_search_venue",
        lambda venue_name, settings=None, client=None: "全席指定のホールです。",
    )
    result = venue.get_venue_info("テスト会場")
    assert result.status == "ok"
    assert result.format == venue.VenueFormat.SEATED
    assert result.summary == "全席指定のホールです。"


def test_get_venue_info_error_when_search_fails(monkeypatch) -> None:
    from app.services import venue

    def _raise(venue_name, settings=None, client=None):
        raise venue.VenueSearchError("APIエラー")

    monkeypatch.setattr(venue, "_search_venue", _raise)
    result = venue.get_venue_info("テスト会場")
    assert result.status == "error"
    assert result.format == venue.VenueFormat.UNKNOWN
    assert result.message == "APIエラー"


def test_extract_address_ok() -> None:
    from unittest.mock import MagicMock

    from app.services import venue

    mock_response = MagicMock()
    mock_response.parsed = venue._AddressExtraction(address="東京都千代田区北の丸公園2-3")
    mock_client = MagicMock()
    mock_client.models.generate_content.return_value = mock_response

    address = venue._extract_address(
        "日本武道館は東京都千代田区北の丸公園2-3にあります。", client=mock_client
    )
    assert address == "東京都千代田区北の丸公園2-3"


def test_extract_address_returns_empty_when_gemini_fails() -> None:
    from unittest.mock import MagicMock

    from app.services import venue

    mock_client = MagicMock()
    mock_client.models.generate_content.side_effect = RuntimeError("APIエラー")

    address = venue._extract_address("何かの説明文", client=mock_client)
    assert address == ""


def test_get_venue_info_includes_address(monkeypatch) -> None:
    from app.services import venue

    monkeypatch.setattr(
        venue,
        "_search_venue",
        lambda venue_name, settings=None, client=None: "全席指定のホールです。",
    )
    monkeypatch.setattr(
        venue,
        "_extract_address",
        lambda raw_text, settings=None, client=None: "東京都千代田区北の丸公園2-3",
    )
    result = venue.get_venue_info("テスト会場")
    assert result.address == "東京都千代田区北の丸公園2-3"
