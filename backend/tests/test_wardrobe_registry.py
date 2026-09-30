"""手持ちの服の登録サービスのテスト(Gemini はフェイクのクライアントで差し替える)。"""

from pathlib import Path
from typing import Any

import pytest
from google.genai import errors

from app.schemas.wardrobe import ClothAttributes, RegisterRequest, WardrobeImage
from app.services.wardrobe_registry import (
    WardrobeError,
    WardrobeImageTooLargeError,
    WardrobeInputError,
    WardrobeNotFoundError,
    WardrobeQuotaError,
    decode_image,
)
from tests.wardrobe_stub import JPEG, PNG, WEBP, encoded, fake_client, make_service


def image(data: bytes = JPEG, mime_type: str = "image/jpeg") -> WardrobeImage:
    return WardrobeImage(mime_type=mime_type, data=encoded(data))  # type: ignore[arg-type]


# --- 写真の検証 ------------------------------------------------------------


@pytest.mark.parametrize(
    ("data", "mime_type"), [(JPEG, "image/jpeg"), (PNG, "image/png"), (WEBP, "image/webp")]
)
def test_decode_image_accepts_supported_formats(data: bytes, mime_type: str) -> None:
    assert decode_image(image(data, mime_type), 1024) == data


def test_decode_image_rejects_broken_base64() -> None:
    with pytest.raises(WardrobeInputError, match="base64"):
        decode_image(WardrobeImage(mime_type="image/jpeg", data="%%%"), 1024)


def test_decode_image_rejects_mismatched_format() -> None:
    """AC-11: 中身が指定の形式の画像でなければ入力エラー。"""
    with pytest.raises(WardrobeInputError, match="形式"):
        decode_image(image(PNG, "image/jpeg"), 1024)


def test_decode_image_rejects_too_large() -> None:
    """AC-11: 上限を超える写真は、デコード前でも後でも弾く。"""
    with pytest.raises(WardrobeImageTooLargeError, match="MB 以下"):
        decode_image(image(JPEG + b"x" * 2000), 1024)
    with pytest.raises(WardrobeImageTooLargeError):
        decode_image(image(JPEG), 10)


# --- 解析 ------------------------------------------------------------------


def test_analyze_returns_attributes(tmp_path: Path) -> None:
    """AC-2 / AC-3: 服ごとの属性が返る。選択肢は並べ直され、暖かさが無ければ null。"""
    client = fake_client()
    service = make_service(tmp_path, client)

    result = service.analyze(image())

    assert result.model == "test-model"
    assert [item.category for item in result.items] == ["Tシャツ", "ジーンズ"]
    shirt = result.items[0]
    assert (shirt.seasons, shirt.warmth, shirt.occasions) == (
        ["春", "夏"],
        "薄手",
        ["普段着", "ライブ・フェス"],
    )
    assert result.items[1].seasons == []
    # 解析だけでは何も保存しない(AC-7)
    assert service.list_items() == []
    assert len(client.calls) == 1


def test_analyze_does_not_call_gemini_for_invalid_image(tmp_path: Path) -> None:
    client = fake_client()

    with pytest.raises(WardrobeInputError):
        make_service(tmp_path, client).analyze(image(PNG, "image/jpeg"))
    assert client.calls == []


def test_analyze_reports_quota_error(tmp_path: Path) -> None:
    """AC-12"""

    def fail(**kwargs: Any) -> Any:
        raise errors.ClientError(429, {"error": {"code": 429, "status": "RESOURCE_EXHAUSTED"}})

    with pytest.raises(WardrobeQuotaError, match="クォータ"):
        make_service(tmp_path, fake_client(fail)).analyze(image())


def test_analyze_reports_other_errors(tmp_path: Path) -> None:
    """AC-12"""

    def fail(**kwargs: Any) -> Any:
        raise errors.ServerError(500, {"error": {"code": 500}})

    with pytest.raises(WardrobeError, match="解析に失敗しました") as info:
        make_service(tmp_path, fake_client(fail)).analyze(image())
    assert not isinstance(info.value, WardrobeQuotaError)


# --- 保存・一覧・削除 --------------------------------------------------------


def register_request(*items: ClothAttributes) -> RegisterRequest:
    default = (
        ClothAttributes(
            category="Tシャツ",
            colors=["白"],
            seasons=["夏", "春"],
            warmth="薄手",
            occasions=["ライブ・フェス"],
        ),
    )
    return RegisterRequest(image=image(), items=list(items or default), summary="白 T")


def test_register_saves_edited_items(tmp_path: Path) -> None:
    """AC-4 / AC-6: 直した内容で保存され、一覧に出る。"""
    service = make_service(tmp_path)

    saved = service.register(register_request())

    assert len(saved) == 1
    assert saved[0].id and saved[0].image.endswith(".jpg")
    assert saved[0].registered_at is not None
    listed = service.list_items()
    expected = [("Tシャツ", ["春", "夏"], "薄手")]
    assert [(i.category, i.seasons, i.warmth) for i in listed] == expected


def test_register_keeps_unknown_warmth_as_null(tmp_path: Path) -> None:
    service = make_service(tmp_path)

    service.register(register_request(ClothAttributes(category="帽子")))

    assert service.list_items()[0].warmth is None


def test_list_items_is_newest_first(tmp_path: Path) -> None:
    service = make_service(tmp_path)
    service.register(register_request(ClothAttributes(category="古い服")))
    service.register(register_request(ClothAttributes(category="新しい服")))

    assert [item.category for item in service.list_items()] == ["新しい服", "古い服"]


def test_delete(tmp_path: Path) -> None:
    """AC-9"""
    service = make_service(tmp_path)
    saved = service.register(register_request())

    service.delete(saved[0].id)

    assert service.list_items() == []
    with pytest.raises(WardrobeNotFoundError):
        service.delete(saved[0].id)


def test_read_image(tmp_path: Path) -> None:
    service = make_service(tmp_path)
    saved = service.register(register_request())

    assert service.read_image(saved[0].image) == (JPEG, "image/jpeg")
    with pytest.raises(WardrobeNotFoundError):
        service.read_image("missing.jpg")


def test_register_request_requires_category() -> None:
    with pytest.raises(ValueError, match="種類"):
        register_request(ClothAttributes(category="  "))
