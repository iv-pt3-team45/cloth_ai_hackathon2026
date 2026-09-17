"""服インデックス参照ツールのテスト(外部 API は呼ばない)。"""

import json
from pathlib import Path

from app.core.config import Settings
from app.services.agent import build_agent
from app.services.wardrobe import (
    WardrobeItem,
    build_wardrobe_tools,
    item_text,
    load_wardrobe,
    search_items,
)


def write_index(path: Path) -> None:
    payload = {
        "count": 2,
        "entries": [
            {
                "image": "image.jpeg",
                "items": [
                    {
                        "category": "Tシャツ",
                        "material": "綿",
                        "shape": "半袖クルーネック",
                        "colors": ["ピンク", "黄色"],
                        "pattern": "プリント",
                        "style": "カジュアル",
                        "notes": "「Let's Eat」のロゴ",
                    }
                ],
            },
            {
                "image": "jeans.jpeg",
                "items": [
                    {
                        "category": "ジーンズ",
                        "material": "デニム",
                        "shape": "ストレート",
                        "colors": ["青"],
                        "pattern": "無地",
                        "style": "カジュアル",
                        "notes": "",
                    }
                ],
            },
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def make_settings(index_file: Path) -> Settings:
    return Settings(cloth_index_path=str(index_file))


def test_load_wardrobe_flattens_items(tmp_path: Path) -> None:
    index_file = tmp_path / "index.json"
    write_index(index_file)

    items = load_wardrobe(index_file)

    assert [i.category for i in items] == ["Tシャツ", "ジーンズ"]
    assert items[0].image == "image.jpeg"


def test_load_wardrobe_returns_empty_when_missing(tmp_path: Path) -> None:
    assert load_wardrobe(tmp_path / "none.json") == []


def test_load_wardrobe_returns_empty_when_broken(tmp_path: Path) -> None:
    broken = tmp_path / "index.json"
    broken.write_text("{ broken", encoding="utf-8")

    assert load_wardrobe(broken) == []


def test_item_text_includes_all_attributes() -> None:
    item = WardrobeItem(
        image="a.jpg",
        category="Tシャツ",
        material="綿",
        shape="半袖",
        colors=["白"],
        pattern="無地",
        style="きれいめ",
        notes="胸ポケット",
    )

    text = item_text(item)

    for expected in ("a.jpg", "Tシャツ", "綿", "半袖", "白", "無地", "きれいめ", "胸ポケット"):
        assert expected in text


def test_search_items_matches_any_attribute(tmp_path: Path) -> None:
    index_file = tmp_path / "index.json"
    write_index(index_file)
    items = load_wardrobe(index_file)

    assert [i.category for i in search_items(items, "デニム")] == ["ジーンズ"]
    assert [i.category for i in search_items(items, "ピンク")] == ["Tシャツ"]
    assert len(search_items(items, "カジュアル")) == 2


def test_search_items_returns_all_for_empty_keyword(tmp_path: Path) -> None:
    index_file = tmp_path / "index.json"
    write_index(index_file)
    items = load_wardrobe(index_file)

    assert len(search_items(items, "   ")) == 2


def test_search_items_ignores_case() -> None:
    items = [WardrobeItem(image="a.jpg", category="T-shirt", material="Cotton", shape="Regular")]

    assert len(search_items(items, "cotton")) == 1


def test_tools_return_items(tmp_path: Path) -> None:
    index_file = tmp_path / "index.json"
    write_index(index_file)
    list_wardrobe, search_wardrobe = build_wardrobe_tools(make_settings(index_file))

    listed = list_wardrobe()
    searched = search_wardrobe("デニム")

    assert listed["status"] == "ok"
    assert listed["count"] == 2
    assert searched["count"] == 1
    assert searched["items"][0]["category"] == "ジーンズ"


def test_tools_report_error_without_index(tmp_path: Path) -> None:
    """インデックスが無くても例外を投げない(エージェントが止まらないように)。"""
    list_wardrobe, search_wardrobe = build_wardrobe_tools(make_settings(tmp_path / "none.json"))

    assert list_wardrobe()["status"] == "error"
    assert "build_cloth_index" in str(search_wardrobe("白")["message"])


def test_tools_are_bound_to_given_settings(tmp_path: Path) -> None:
    """設定を差し替えると参照先も切り替わる(CLI の --index 用)。"""
    first = tmp_path / "a" / "index.json"
    write_index(first)
    empty = tmp_path / "b" / "index.json"
    empty.parent.mkdir(parents=True)
    empty.write_text(json.dumps({"entries": []}), encoding="utf-8")

    assert build_wardrobe_tools(make_settings(first))[0]()["status"] == "ok"
    assert build_wardrobe_tools(make_settings(empty))[0]()["status"] == "error"


def test_agent_has_wardrobe_tools() -> None:
    agent = build_agent(Settings())
    names = {getattr(tool, "__name__", getattr(tool, "name", "")) for tool in agent.tools}

    assert {"list_wardrobe", "search_wardrobe"} <= names
