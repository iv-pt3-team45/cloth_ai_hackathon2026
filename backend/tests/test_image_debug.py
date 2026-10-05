"""画像生成のプロンプトと応答のデバッグ出力(一時的な機能)のテスト。Gemini は呼ばない。"""

import logging

import pytest
from google.genai import types

from app.services.image_debug import (
    describe_contents,
    dump_response,
    log_image_error,
    log_image_request,
    log_image_response,
)

JPEG = b"\xff\xd8\xff\xe0" + b"x" * 1000


def _response() -> types.GenerateContentResponse:
    return types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                finish_reason=types.FinishReason.STOP,
                content=types.Content(
                    role="model",
                    parts=[
                        types.Part(text="できました"),
                        types.Part(inline_data=types.Blob(data=JPEG, mime_type="image/jpeg")),
                    ],
                ),
            )
        ]
    )


def test_describe_contents_shows_text_and_image_sizes() -> None:
    contents = [
        types.Content(
            role="user",
            parts=[
                types.Part.from_bytes(data=JPEG, mime_type="image/jpeg"),
                types.Part.from_text(text="マネキンに着せてください"),
            ],
        )
    ]

    text = describe_contents(contents)

    assert "[1] 画像 <image/jpeg 1,004 bytes>" in text
    assert "[2] テキスト:\nマネキンに着せてください" in text


def test_describe_contents_accepts_plain_prompt() -> None:
    assert describe_contents("富士山の画像") == "[1] テキスト:\n富士山の画像"


def test_dump_response_keeps_everything_but_image_bytes() -> None:
    text = dump_response(_response())

    assert '"text": "できました"' in text
    assert '"finish_reason": "STOP"' in text
    assert "<image/jpeg 1,004 bytes>" in text
    # 画像のバイト列そのものは出さない
    assert "xxxxxxxx" not in text


def test_logs_request_and_response_when_enabled(caplog: pytest.LogCaptureFixture) -> None:
    config = types.GenerateContentConfig(response_modalities=["IMAGE"])
    with caplog.at_level(logging.INFO, logger="app.services.image_debug"):
        log_image_request(True, "コーデ画像", "test-image", "プロンプト本文", config)
        log_image_response(True, "コーデ画像", _response())

    logged = caplog.text
    assert "[画像生成のプロンプト] コーデ画像 / model=test-image" in logged
    assert '"response_modalities": ["IMAGE"]' in logged
    assert "プロンプト本文" in logged
    assert "[画像生成の応答] コーデ画像" in logged
    assert '"text": "できました"' in logged


def test_logs_error_detail_when_enabled(caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level(logging.INFO, logger="app.services.image_debug"):
        log_image_error(True, "コーデ画像", RuntimeError("429 RESOURCE_EXHAUSTED"))

    assert "[画像生成のエラー] コーデ画像" in caplog.text
    assert "RuntimeError: 429 RESOURCE_EXHAUSTED" in caplog.text


def test_logs_nothing_when_disabled(caplog: pytest.LogCaptureFixture) -> None:
    config = types.GenerateContentConfig(response_modalities=["IMAGE"])
    with caplog.at_level(logging.INFO, logger="app.services.image_debug"):
        log_image_request(False, "コーデ画像", "test-image", "プロンプト本文", config)
        log_image_response(False, "コーデ画像", _response())
        log_image_error(False, "コーデ画像", RuntimeError("x"))

    assert caplog.text == ""
