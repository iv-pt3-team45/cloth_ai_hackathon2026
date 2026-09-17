"""服インデックス(`index.json`)をエージェントから参照するためのツール。

ADK の `LlmAgent` に登録し、手持ちの服に関する話題のときだけモデルが呼ぶ。
インデックスの作成は `scripts/build_cloth_index.py`(spec 005)が担当する。
"""

import json
import logging
from collections.abc import Callable
from pathlib import Path
from typing import Any

from app.core.config import Settings, get_settings
from app.services.cloth_index import ClothItem

logger = logging.getLogger(__name__)

# 検索結果が多すぎるとプロンプトが膨らむため上限を設ける
MAX_RESULTS = 50


class WardrobeItem(ClothItem):
    """どの画像に写っていたかを含む 1 着ぶんの情報。"""

    image: str = ""


def load_wardrobe(index_file: Path) -> list[WardrobeItem]:
    """`index.json` を読み、服の一覧にする。

    ファイルが無い / 壊れている場合は空の一覧を返す(呼び出し側でエラー応答にする)。
    """
    if not index_file.is_file():
        return []

    try:
        payload = json.loads(index_file.read_text(encoding="utf-8"))
    except Exception:
        logger.warning("インデックスを読み込めませんでした: %s", index_file)
        return []

    items: list[WardrobeItem] = []
    for entry in payload.get("entries", []):
        image = entry.get("image", "")
        for raw in entry.get("items", []):
            try:
                items.append(WardrobeItem(image=image, **raw))
            except Exception:
                logger.warning("インデックスの項目を解釈できませんでした: %s", image)
    return items


def item_text(item: WardrobeItem) -> str:
    """検索対象にする文字列(全属性の連結)。"""
    return " ".join(
        [
            item.image,
            item.category,
            item.material,
            item.shape,
            " ".join(item.colors),
            item.pattern,
            item.style,
            item.notes,
        ]
    )


def search_items(items: list[WardrobeItem], keyword: str) -> list[WardrobeItem]:
    """キーワードで絞り込む(大文字小文字を無視した部分一致)。空なら全件。"""
    needle = keyword.strip().lower()
    if not needle:
        return items
    return [item for item in items if needle in item_text(item).lower()]


def _to_payload(items: list[WardrobeItem]) -> dict[str, Any]:
    return {
        "status": "ok",
        "count": len(items),
        "items": [item.model_dump() for item in items[:MAX_RESULTS]],
    }


def _no_index(index_file: Path) -> dict[str, Any]:
    return {
        "status": "error",
        "message": (
            f"服のインデックスが見つかりません({index_file})。"
            "`uv run python scripts/build_cloth_index.py` で作成してください。"
        ),
    }


def build_wardrobe_tools(settings: Settings | None = None) -> list[Callable[..., Any]]:
    """設定を閉じ込めたツール関数を作る。

    グローバル設定を直接読むと CLI の `--index` による差し替えが効かないため、
    参照先を束縛したクロージャとして生成する。
    """
    bound = settings or get_settings()

    def list_wardrobe() -> dict[str, Any]:
        """利用者が持っている服(ワードローブ)の一覧を取得する。

        「手持ちの服」「私の服」「持っている服」について聞かれたときに使う。
        コーディネートを提案する前には、まずこれで何を持っているか確認すること。

        Returns:
            status="ok" と服の一覧 items(種類・素材・形・色・柄・系統・特徴)。
            インデックスが無い場合は status="error"。
        """
        items = load_wardrobe(bound.cloth_index_file)
        if not items:
            return _no_index(bound.cloth_index_file)
        return _to_payload(items)

    def search_wardrobe(keyword: str) -> dict[str, Any]:
        """利用者が持っている服を、キーワードで絞り込んで取得する。

        色・素材・種類・系統などで探すときに使う(例: 「白」「デニム」「Tシャツ」)。
        一覧をすべて見たい場合は list_wardrobe を使う。

        Args:
            keyword: 検索語。服の属性(種類・素材・形・色・柄・系統・特徴)に
                部分一致で照合する。空文字なら全件を返す。

        Returns:
            status="ok" と一致した服の一覧 items。
            インデックスが無い場合は status="error"。
        """
        items = load_wardrobe(bound.cloth_index_file)
        if not items:
            return _no_index(bound.cloth_index_file)
        return _to_payload(search_items(items, keyword))

    return [list_wardrobe, search_wardrobe]
