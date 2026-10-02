"""手持ちの服の保存(ローカルの WardrobeStore)のテスト。"""

import json
from pathlib import Path

import pytest

from app.core.config import Settings
from app.services.cloth_index import ClothItem, load_index
from app.services.wardrobe import build_wardrobe_tools, load_wardrobe
from app.services.wardrobe_store import LocalWardrobeStore, WardrobeStoreError

JPEG = b"\xff\xd8\xff\xe0jpeg-data"


def cloth(category: str, **overrides: object) -> ClothItem:
    values: dict[str, object] = {
        "category": category,
        "material": "綿",
        "shape": "半袖",
        "colors": ["白"],
        "seasons": ["春", "夏"],
        "warmth": "薄手",
        "occasions": ["普段着"],
    }
    values.update(overrides)
    return ClothItem(**values)  # type: ignore[arg-type]


def make_store(tmp_path: Path) -> LocalWardrobeStore:
    return LocalWardrobeStore(tmp_path / "wardrobe" / "index.json")


def test_add_saves_image_and_items(tmp_path: Path) -> None:
    """AC-6: 写真と服の属性がローカルに保存され、読み直しても残る。"""
    store = make_store(tmp_path)

    entry = store.add(JPEG, "image/jpeg", [cloth("Tシャツ"), cloth("パンツ")], "白 T", "m")

    assert entry.image.startswith("cloth-") and entry.image.endswith(".jpg")
    assert (store.images_dir / entry.image).read_bytes() == JPEG
    assert len({item.id for item in entry.items}) == 2
    # 別のインスタンス(= 再起動後)でも読める
    reloaded = make_store(tmp_path).list_entries()
    assert [item.category for item in reloaded[0].items] == ["Tシャツ", "パンツ"]
    assert reloaded[0].items[0].seasons == ["春", "夏"]
    assert not list(store.index_file.parent.glob("*.tmp"))


def test_index_is_readable_by_spec005_and_spec006(tmp_path: Path) -> None:
    """AC-10: spec 005 の load_index と 006 のエージェントのツールがそのまま読める。"""
    store = make_store(tmp_path)
    store.add(JPEG, "image/jpeg", [cloth("Tシャツ", occasions=["ライブ・フェス"])], "", "m")

    assert list(load_index(store.index_file.parent).values())[0].items[0].category == "Tシャツ"
    assert load_wardrobe(store.index_file)[0].occasions == ["ライブ・フェス"]
    list_wardrobe, search_wardrobe = build_wardrobe_tools(
        Settings(cloth_index_path=str(store.index_file))
    )
    assert list_wardrobe()["count"] == 1
    assert search_wardrobe("ライブ・フェス")["count"] == 1


def test_delete_one_item_keeps_image(tmp_path: Path) -> None:
    """AC-9: 服 1 点ずつ削除できる。写真に服が残っていれば写真は残す。"""
    store = make_store(tmp_path)
    entry = store.add(JPEG, "image/jpeg", [cloth("Tシャツ"), cloth("パンツ")], "", "m")

    assert store.delete_item(entry.items[0].id) is True

    entries = store.list_entries()
    assert [item.category for item in entries[0].items] == ["パンツ"]
    assert (store.images_dir / entry.image).is_file()


def test_delete_last_item_removes_entry_and_image(tmp_path: Path) -> None:
    store = make_store(tmp_path)
    entry = store.add(JPEG, "image/jpeg", [cloth("Tシャツ")], "", "m")

    assert store.delete_item(entry.items[0].id) is True

    assert store.list_entries() == []
    assert not (store.images_dir / entry.image).exists()
    # エージェントからも参照されなくなる
    assert load_wardrobe(store.index_file) == []


def test_delete_unknown_item(tmp_path: Path) -> None:
    assert make_store(tmp_path).delete_item("missing") is False


def test_legacy_index_without_ids_gets_ids(tmp_path: Path) -> None:
    """spec 005 の CLI で作った(ID の無い)index.json も読め、削除もできる。"""
    store = make_store(tmp_path)
    store.index_file.parent.mkdir(parents=True)
    store.index_file.write_text(
        json.dumps(
            {"entries": [{"image": "a.jpg", "items": [{"category": "Tシャツ", "material": "綿"}]}]},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    entries = store.list_entries()

    assert entries[0].items[0].id == "a.jpg#0"
    assert store.delete_item("a.jpg#0") is True


def test_read_image(tmp_path: Path) -> None:
    store = make_store(tmp_path)
    entry = store.add(b"\x89PNG\r\n\x1a\npng", "image/png", [cloth("Tシャツ")], "", "m")

    assert store.read_image(entry.image) == (b"\x89PNG\r\n\x1a\npng", "image/png")
    assert store.read_image("missing.jpg") is None


@pytest.mark.parametrize("name", ["../index.json", "a/b.jpg", "..", "", "a b.jpg"])
def test_read_image_rejects_unsafe_names(tmp_path: Path, name: str) -> None:
    """保存先のフォルダの外を指すファイル名は受け付けない。"""
    store = make_store(tmp_path)
    store.add(JPEG, "image/jpeg", [cloth("Tシャツ")], "", "m")

    assert store.read_image(name) is None


def test_broken_index_is_not_overwritten(tmp_path: Path) -> None:
    """壊れた index.json は一覧では空として扱うが、保存で上書きして登録済みの服を失わない。"""
    store = make_store(tmp_path)
    store.index_file.parent.mkdir(parents=True)
    store.index_file.write_text("{ broken", encoding="utf-8")

    assert store.list_entries() == []
    with pytest.raises(WardrobeStoreError):
        store.add(JPEG, "image/jpeg", [cloth("Tシャツ")], "", "m")
    assert store.index_file.read_text(encoding="utf-8") == "{ broken"
