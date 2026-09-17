"""添付ファイルの取り扱いに関するテスト(外部通信なし)。"""

import base64
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.schemas.chat import Attachment
from app.services.agent import to_parts
from app.services.attachments import AttachmentError, guess_mime_type, is_uri, load_attachment


def test_guess_mime_type_for_image_and_video() -> None:
    assert guess_mime_type("photo.PNG") == "image/png"
    assert guess_mime_type("movie.mp4") == "video/mp4"


def test_guess_mime_type_rejects_unknown_suffix() -> None:
    with pytest.raises(AttachmentError, match="対応していない拡張子"):
        guess_mime_type("data.xyz")


def test_is_uri() -> None:
    assert is_uri("gs://bucket/movie.mp4")
    assert not is_uri("C:/tmp/photo.png")


def test_load_attachment_encodes_local_file(tmp_path: Path) -> None:
    path = tmp_path / "photo.png"
    path.write_bytes(b"dummy-image-bytes")

    attachment = load_attachment(str(path))

    assert attachment.mime_type == "image/png"
    assert attachment.uri is None
    assert base64.b64decode(attachment.data or "") == b"dummy-image-bytes"


def test_load_attachment_keeps_uri_as_is() -> None:
    attachment = load_attachment("gs://bucket/movie.mp4")

    assert attachment.uri == "gs://bucket/movie.mp4"
    assert attachment.data is None


def test_load_attachment_reports_missing_file(tmp_path: Path) -> None:
    with pytest.raises(AttachmentError, match="ファイルが見つかりません"):
        load_attachment(str(tmp_path / "none.png"))


def test_attachment_requires_exactly_one_source() -> None:
    with pytest.raises(ValidationError):
        Attachment(mime_type="image/png")
    with pytest.raises(ValidationError):
        Attachment(mime_type="image/png", data="abc", uri="gs://b/o.png")


def test_to_parts_puts_text_last() -> None:
    attachments = [
        Attachment(mime_type="image/png", data=base64.b64encode(b"img").decode()),
        Attachment(mime_type="video/mp4", uri="gs://bucket/movie.mp4"),
    ]

    parts = to_parts("説明して", attachments)

    assert len(parts) == 3
    assert parts[0].inline_data is not None
    assert parts[0].inline_data.data == b"img"
    assert parts[1].file_data is not None
    assert parts[1].file_data.file_uri == "gs://bucket/movie.mp4"
    assert parts[2].text == "説明して"


def test_to_parts_without_attachments() -> None:
    parts = to_parts("こんにちは")
    assert len(parts) == 1
    assert parts[0].text == "こんにちは"
