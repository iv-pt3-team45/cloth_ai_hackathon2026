"""画像 / 動画を生成するエージェントツール。

ADK の `LlmAgent` に関数として登録する(Function Calling)。
呼ぶかどうかの判断はモデルが行うため、docstring に「いつ使うか」を明記している。

- 画像: `generate_content` にインライン画像を返させる。
- 動画: **Interactions API 専用**モデルのため `client.interactions.create()` を使う。
"""

import base64
import logging
import secrets
from datetime import datetime
from functools import lru_cache
from pathlib import Path
from typing import Any

from google import genai
from google.genai import types

from app.core.config import Settings, get_settings

logger = logging.getLogger(__name__)

# MIME タイプ → 拡張子。未知のものは既定値にフォールバックする。
_EXTENSION_BY_MIME = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/webp": ".webp",
    "video/mp4": ".mp4",
    "video/webm": ".webm",
    "video/quicktime": ".mov",
}


class MediaGenerationError(RuntimeError):
    """メディア生成に失敗したときの例外。ツール内で捕捉して dict に変換する。"""


@lru_cache
def get_media_client() -> genai.Client:
    """メディア生成用の genai クライアント(ADC 認証)。プロセス内で共有する。"""
    settings = get_settings()
    settings.export_google_env()

    if settings.google_genai_use_vertexai:
        if not settings.google_cloud_project:
            raise MediaGenerationError("GOOGLE_CLOUD_PROJECT が未設定です。")
        return genai.Client(
            vertexai=True,
            project=settings.google_cloud_project,
            location=settings.google_cloud_location,
        )

    if not settings.google_api_key:
        raise MediaGenerationError("GOOGLE_API_KEY が未設定です。")
    return genai.Client(api_key=settings.google_api_key)


def build_file_name(prefix: str, mime_type: str, default_suffix: str) -> str:
    """`20260917-134501-a1b2c3.png` 形式の重複しにくいファイル名を作る。"""
    suffix = _EXTENSION_BY_MIME.get(mime_type, default_suffix)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return f"{prefix}-{stamp}-{secrets.token_hex(3)}{suffix}"


def save_media(data: bytes, directory: Path, file_name: str) -> Path:
    """バイト列を保存してパスを返す。保存先が無ければ作成する。"""
    if not data:
        raise MediaGenerationError("生成結果が空でした。")

    directory.mkdir(parents=True, exist_ok=True)
    path = directory / file_name
    path.write_bytes(data)
    logger.info("メディアを保存しました: %s (%d bytes)", path, len(data))
    return path


def _success(path: Path, mime_type: str, model: str) -> dict[str, Any]:
    return {
        "status": "ok",
        "file_name": path.name,
        "path": str(path),
        "mime_type": mime_type,
        "model": model,
    }


def _failure(message: str) -> dict[str, Any]:
    return {"status": "error", "message": message}


def _generate_image(prompt: str, settings: Settings) -> dict[str, Any]:
    """画像生成の本体(例外を投げる。公開ツールはこれを包む)。"""
    client = get_media_client()
    response = client.models.generate_content(
        model=settings.image_model,
        contents=prompt,
        config=types.GenerateContentConfig(response_modalities=["TEXT", "IMAGE"]),
    )

    candidates = response.candidates or []
    parts = (candidates[0].content.parts or []) if candidates and candidates[0].content else []
    for part in parts:
        inline = part.inline_data
        if inline and inline.data:
            mime_type = inline.mime_type or "image/png"
            path = save_media(
                inline.data,
                settings.created_images_path,
                build_file_name("image", mime_type, ".png"),
            )
            return _success(path, mime_type, settings.image_model)

    raise MediaGenerationError("モデルが画像を返しませんでした。")


def _generate_video(prompt: str, settings: Settings) -> dict[str, Any]:
    """動画生成の本体(例外を投げる。公開ツールはこれを包む)。"""
    client = get_media_client()
    # 動画モデルは generateContent では呼べず、Interactions API を使う
    interaction = client.interactions.create(
        model=settings.video_model,
        input=prompt,
        timeout=settings.media_generation_timeout,
    )

    video = getattr(interaction, "output_video", None)
    if video is None or not video.data:
        status = getattr(interaction, "status", "unknown")
        raise MediaGenerationError(f"モデルが動画を返しませんでした(status={status})。")

    mime_type = str(video.mime_type or "video/mp4")
    path = save_media(
        base64.b64decode(video.data),
        settings.created_videos_path,
        build_file_name("video", mime_type, ".mp4"),
    )
    return _success(path, mime_type, settings.video_model)


def generate_image(prompt: str) -> dict[str, Any]:
    """ユーザーが画像の生成・作成を求めたときに、画像を生成してローカルに保存する。

    「〜の画像を作って」「〜を描いて」「イラストにして」などの依頼で使う。
    既存の画像について説明を求められただけのときは使わない。

    Args:
        prompt: 生成したい画像の説明。英語でも日本語でもよいが、
            色・構図・雰囲気など具体的に書くほど意図した画像になりやすい。

    Returns:
        成功時は status="ok" と保存したファイル名 file_name / パス path。
        失敗時は status="error" と理由 message。
    """
    try:
        return _generate_image(prompt, get_settings())
    except Exception as exc:  # ツールが例外を投げるとエージェントが止まるため dict で返す
        logger.exception("画像生成に失敗しました")
        return _failure(str(exc))


def generate_video(prompt: str) -> dict[str, Any]:
    """ユーザーが動画の生成・作成を求めたときに、動画を生成してローカルに保存する。

    「〜の動画を作って」「〜の映像がほしい」などの依頼で使う。
    生成には数十秒かかるため、静止画で足りる依頼では generate_image を使う。

    Args:
        prompt: 生成したい動画の説明。動き・長さ・カメラワークを含めると意図が伝わりやすい。

    Returns:
        成功時は status="ok" と保存したファイル名 file_name / パス path。
        失敗時は status="error" と理由 message。
    """
    try:
        return _generate_video(prompt, get_settings())
    except Exception as exc:
        logger.exception("動画生成に失敗しました")
        return _failure(str(exc))
