"""手持ちの服の登録(spec 010)のテスト用スタブ。Gemini は呼ばない。"""

import base64
from collections.abc import Callable
from pathlib import Path
from types import SimpleNamespace
from typing import Any

from google.genai import types

from app.core.config import Settings
from app.services.cloth_index import ClothAnalysis, ClothItem
from app.services.wardrobe_registry import WardrobeService
from app.services.wardrobe_store import LocalWardrobeStore

JPEG = b"\xff\xd8\xff\xe0" + b"jpeg-body" * 4
PNG = b"\x89PNG\r\n\x1a\n" + b"png-body"
WEBP = b"RIFF\x00\x00\x00\x00WEBPVP8 "


def encoded(data: bytes = JPEG) -> str:
    return base64.b64encode(data).decode()


def image_body(data: bytes = JPEG, mime_type: str = "image/jpeg") -> dict[str, str]:
    return {"mime_type": mime_type, "data": encoded(data)}


def analysis(*items: ClothItem, summary: str = "白い T シャツとデニム") -> ClothAnalysis:
    default = (
        ClothItem(
            category="Tシャツ",
            material="綿",
            shape="半袖",
            colors=["白"],
            style="カジュアル",
            seasons=["夏", "春"],
            warmth="薄手",
            occasions=["ライブ・フェス", "普段着"],
        ),
        ClothItem(category="ジーンズ", material="デニム", shape="ストレート", warmth="普通"),
    )
    return ClothAnalysis(items=list(items or default), summary=summary)


def fake_client(respond: Callable[..., Any] | None = None) -> Any:
    """`client.models.generate_content` だけを持つ同期のフェイク。"""
    calls: list[dict[str, Any]] = []

    def generate_content(**kwargs: Any) -> Any:
        calls.append(kwargs)
        if respond is not None:
            return respond(**kwargs)
        return types.GenerateContentResponse(parsed=analysis())

    return SimpleNamespace(models=SimpleNamespace(generate_content=generate_content), calls=calls)


def make_settings(tmp_path: Path, **overrides: Any) -> Settings:
    values: dict[str, Any] = {
        "cloth_index_path": str(tmp_path / "wardrobe" / "index.json"),
        "cloth_index_model": "test-model",
        "wardrobe_max_image_bytes": 1024,
    }
    values.update(overrides)
    return Settings(**values)


def make_service(tmp_path: Path, client: Any = None, **settings: Any) -> WardrobeService:
    config = make_settings(tmp_path, **settings)
    return WardrobeService(
        settings=config,
        store=LocalWardrobeStore(config.cloth_index_file),
        client=client if client is not None else fake_client(),
    )
