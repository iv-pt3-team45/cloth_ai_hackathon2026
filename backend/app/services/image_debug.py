"""画像生成モデルに送るプロンプトと応答の全文をログ(ターミナル)に出す。一時的なデバッグ用。

設定 `IMAGE_DEBUG_LOG`(既定 true)で切り替える。
画像のバイト列はそのまま出すと膨大になるため、形式と大きさ(例: `<image/jpeg 152,916 bytes>`)
に置き換えて出す。それ以外(テキスト・設定・応答の各項目)は全文を出す。
"""

import json
import logging
from typing import Any

from google.genai import types

logger = logging.getLogger(__name__)

_RULE = "=" * 72


def _bytes_label(mime_type: str | None, size: int) -> str:
    return f"<{mime_type or '不明な形式'} {size:,} bytes>"


def _describe_part(index: int, part: types.Part) -> str:
    inline = part.inline_data
    if inline is not None:
        return f"[{index}] 画像 {_bytes_label(inline.mime_type, len(inline.data or b''))}"
    if part.text is not None:
        return f"[{index}] テキスト:\n{part.text}"
    return f"[{index}] その他: {part.model_dump(exclude_none=True)}"


def describe_contents(contents: Any) -> str:
    """送る内容(文字列 / Content の一覧 / Part の一覧)を、人が読める形にする。"""
    if isinstance(contents, str):
        return f"[1] テキスト:\n{contents}"
    items = contents if isinstance(contents, list) else [contents]
    parts: list[types.Part] = []
    for item in items:
        if isinstance(item, types.Content):
            parts.extend(item.parts or [])
        elif isinstance(item, types.Part):
            parts.append(item)
        else:
            parts.append(types.Part(text=str(item)))
    return "\n".join(_describe_part(i, part) for i, part in enumerate(parts, start=1))


def _redact(value: Any) -> Any:
    """応答の辞書から画像のバイト列を、形式と大きさの表記に置き換える。"""
    if isinstance(value, dict):
        data = value.get("data")
        if "mime_type" in value and isinstance(data, (bytes, bytearray)):
            return {**value, "data": _bytes_label(value.get("mime_type"), len(data))}
        return {key: _redact(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_redact(item) for item in value]
    if isinstance(value, (bytes, bytearray)):
        return _bytes_label(None, len(value))
    return value


def dump_response(response: types.GenerateContentResponse) -> str:
    """応答の全文(画像のバイト列は大きさだけ)を JSON にする。"""
    raw = response.model_dump(exclude_none=True)
    return json.dumps(_redact(raw), ensure_ascii=False, indent=2, default=str)


def log_image_request(
    enabled: bool, purpose: str, model: str, contents: Any, config: types.GenerateContentConfig
) -> None:
    """画像生成モデルに送るプロンプトと設定をログに出す(`IMAGE_DEBUG_LOG` が true のときだけ)。"""
    if not enabled:
        return
    settings = json.dumps(
        _redact(config.model_dump(exclude_none=True)), ensure_ascii=False, default=str
    )
    logger.info(
        "\n%s\n[画像生成のプロンプト] %s / model=%s\n設定: %s\n%s\n%s",
        _RULE,
        purpose,
        model,
        settings,
        describe_contents(contents),
        _RULE,
    )


def log_image_response(
    enabled: bool, purpose: str, response: types.GenerateContentResponse
) -> None:
    """画像生成モデルの応答の全文をログに出す(`IMAGE_DEBUG_LOG` が true のときだけ)。"""
    if not enabled:
        return
    logger.info("\n%s\n[画像生成の応答] %s\n%s\n%s", _RULE, purpose, dump_response(response), _RULE)


def log_image_error(enabled: bool, purpose: str, exc: BaseException) -> None:
    """画像生成の呼び出しが例外で終わったとき、エラーの全文をログに出す。"""
    if not enabled:
        return
    logger.info(
        "\n%s\n[画像生成のエラー] %s\n%s: %s\n%s", _RULE, purpose, type(exc).__name__, exc, _RULE
    )
