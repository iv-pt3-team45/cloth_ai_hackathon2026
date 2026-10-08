"""入力の共通チェック(spec 036 の B)のテスト。外部 API は呼ばない。"""

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.schemas.common import MAX_STRING_LENGTH, check_strings
from app.services.wardrobe_registry import get_wardrobe_service
from tests.test_wardrobe_api import ITEM, register
from tests.wardrobe_stub import image_body, make_service


def _api(tmp_path: Path) -> TestClient:
    app = create_app()
    service = make_service(tmp_path)
    app.dependency_overrides[get_wardrobe_service] = lambda: service
    return TestClient(app)


@pytest.mark.parametrize("text", ["改行\nタブ\t復帰\r", "家族 👨\u200d👩\u200d👧", "Ado 'Wish'"])
def test_check_strings_allows_ordinary_text(text: str) -> None:
    check_strings({"a": text, "b": [text]})


@pytest.mark.parametrize("char", ["\x00", "\x1b", "\x7f", "\u202e", "\u2066"])
def test_check_strings_rejects_control_characters(char: str) -> None:
    with pytest.raises(ValueError, match=r"items\[0\]\.notes に使えない制御文字"):
        check_strings({"items": [{"notes": f"Tシャツ{char}"}]})


def test_check_strings_limits_length_but_skips_base64_data() -> None:
    with pytest.raises(ValueError, match="長すぎます"):
        check_strings({"summary": "あ" * (MAX_STRING_LENGTH + 1)})
    # 画像の base64(キー data)は大きくても検査しない
    check_strings({"image": {"data": "A" * (MAX_STRING_LENGTH * 3)}})


def test_requests_with_control_characters_are_rejected(tmp_path: Path) -> None:
    """AC-7: 外部 API を呼ぶ前に 422 で断る。"""
    api = _api(tmp_path)

    responses = [
        api.post("/api/v1/youtube/lookup", json={"query": "アイドル\x00"}),
        api.post("/api/v1/live/search", json={"query": "電光石火\u202e"}),
        register(api, [{**ITEM, "notes": "ロゴ\x1b[31m"}]),
    ]

    assert [r.status_code for r in responses] == [422, 422, 422]
    assert "制御文字" in str(responses[2].json()["detail"])


def test_leading_and_trailing_spaces_are_removed(tmp_path: Path) -> None:
    api = _api(tmp_path)

    res = register(api, [{**ITEM, "category": "  Tシャツ  "}])

    assert res.status_code == 201
    assert res.json()["items"][0]["category"] == "Tシャツ"


def test_base64_image_is_not_limited(tmp_path: Path) -> None:
    api = _api(tmp_path)

    res = api.post("/api/v1/wardrobe/items", json={"image": image_body(), "items": [ITEM]})

    assert res.status_code == 201
