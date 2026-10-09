"""手持ちの服の Cloud Storage への保存(spec 036)のテスト。Cloud Storage は偽物に差し替える。"""

import json
from pathlib import Path

import pytest

from app.core.config import Settings
from app.services.cloth_index import ClothItem
from app.services.wardrobe import build_wardrobe_tools
from app.services.wardrobe_gcs import GcsWardrobeStore
from app.services.wardrobe_store import (
    LocalWardrobeStore,
    StoredEntry,
    WardrobeStoreError,
    create_wardrobe_store,
    describe_wardrobe_location,
    dump_index,
    new_entry,
)
from tests.gcs_stub import FakeBucket

JPEG = b"\xff\xd8\xff\xe0jpeg-data"
INDEX = "wardrobe/index.json"


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


def make_store(bucket: FakeBucket, prefix: str = "wardrobe") -> GcsWardrobeStore:
    return GcsWardrobeStore("test-bucket", prefix=prefix, bucket=bucket)  # type: ignore[arg-type]


def add(store: GcsWardrobeStore, *categories: str) -> StoredEntry:
    return store.add(JPEG, "image/jpeg", [cloth(c) for c in categories], "白 T", "m")


# --- 保存先の切り替え(AC-1) ---


def test_default_storage_is_local() -> None:
    """AC-1: 設定しなければローカルのフォルダに保存する。"""
    store = create_wardrobe_store(Settings())

    assert isinstance(store, LocalWardrobeStore)
    assert describe_wardrobe_location(Settings()).endswith("index.json")


def test_gcs_storage_is_selected_by_setting() -> None:
    settings = Settings(
        wardrobe_storage="gcs", wardrobe_gcs_bucket="b", wardrobe_gcs_prefix="/wardrobe/"
    )

    store = create_wardrobe_store(settings)

    assert isinstance(store, GcsWardrobeStore)
    assert store.index_path == INDEX
    assert describe_wardrobe_location(settings) == "gs://b/wardrobe/index.json"


# --- 保存・一覧・写真・削除(AC-2〜AC-4) ---


def test_add_saves_image_and_index_to_bucket() -> None:
    """AC-2: 写真と index.json がバケットの接頭辞の下に保存される。"""
    bucket = FakeBucket()
    entry = add(make_store(bucket), "Tシャツ", "パンツ")

    image = f"wardrobe/images/{entry.image}"
    assert bucket.objects[image].data == JPEG
    assert bucket.objects[image].content_type == "image/jpeg"
    assert bucket.objects[INDEX].content_type == "application/json; charset=utf-8"
    payload = json.loads(bucket.text(INDEX))
    assert payload["count"] == 1
    assert [item["category"] for item in payload["entries"][0]["items"]] == ["Tシャツ", "パンツ"]


def test_entries_survive_new_instance() -> None:
    """AC-3・AC-5: 別のインスタンス(= 再起動後)でも、同じ服と写真が読める。"""
    bucket = FakeBucket()
    entry = add(make_store(bucket), "Tシャツ")

    reloaded = make_store(bucket)
    entries = reloaded.list_entries()
    assert entries[0].items[0].category == "Tシャツ"
    assert entries[0].items[0].seasons == ["春", "夏"]
    assert reloaded.read_image(entry.image) == (JPEG, "image/jpeg")


def test_list_is_empty_without_index() -> None:
    assert make_store(FakeBucket()).list_entries() == []


def test_read_image_returns_none_when_missing_or_invalid() -> None:
    store = make_store(FakeBucket())

    assert store.read_image("cloth-missing.jpg") is None
    assert store.read_image("../index.json") is None
    assert store.read_image("..") is None


def test_delete_keeps_photo_while_items_remain() -> None:
    """AC-4: 写真に服が残っているうちは写真を消さない。"""
    bucket = FakeBucket()
    store = make_store(bucket)
    entry = add(store, "Tシャツ", "パンツ")

    assert store.delete_item(entry.items[0].id) is True

    assert [item.category for item in store.list_entries()[0].items] == ["パンツ"]
    assert f"wardrobe/images/{entry.image}" in bucket.objects


def test_delete_last_item_removes_photo() -> None:
    """AC-4: 写真の服がすべて消えたら、写真もバケットから消える。"""
    bucket = FakeBucket()
    store = make_store(bucket)
    entry = add(store, "Tシャツ")

    assert store.delete_item(entry.items[0].id) is True

    assert store.list_entries() == []
    assert f"wardrobe/images/{entry.image}" not in bucket.objects


def test_delete_unknown_item_returns_false() -> None:
    bucket = FakeBucket()
    store = make_store(bucket)
    add(store, "Tシャツ")
    generation = bucket.objects[INDEX].generation

    assert store.delete_item("unknown") is False
    # 見つからなければ書き戻さない
    assert bucket.objects[INDEX].generation == generation


def test_prefix_can_be_empty() -> None:
    bucket = FakeBucket()
    entry = add(make_store(bucket, prefix=""), "Tシャツ")

    assert "index.json" in bucket.objects
    assert f"images/{entry.image}" in bucket.objects


# --- 同時に書き込まれたとき(AC-7) ---


def test_concurrent_add_keeps_both_entries() -> None:
    """AC-7: 読んでから書き戻すまでに他のサーバーが登録しても、両方の登録が残る。"""
    bucket = FakeBucket()
    store = make_store(bucket)
    other = new_entry("image/jpeg", [cloth("パンツ")], "", "m")

    def other_server_registers(name: str) -> None:
        # store が index.json を書き戻す直前に、別のサーバーが先に 1 件登録する
        bucket._put(name, dump_index([other]).encode("utf-8"), "application/json")

    bucket.before_upload = other_server_registers
    add(store, "Tシャツ")

    categories = sorted(e.items[0].category for e in make_store(bucket).list_entries())
    assert categories == ["Tシャツ", "パンツ"]


def test_gives_up_after_repeated_conflicts() -> None:
    """書き込みがぶつかり続けたら諦めてエラーにし、置いた写真も消す。"""
    bucket = FakeBucket()
    store = make_store(bucket)

    def always_conflict(name: str) -> None:
        bucket._put(name, b'{"entries": []}', "application/json")
        bucket.before_upload = always_conflict

    bucket.before_upload = always_conflict

    with pytest.raises(WardrobeStoreError, match="重なり続けた"):
        add(store, "Tシャツ")
    assert not [name for name in bucket.objects if "/images/" in name]


# --- エージェントのツール(AC-9・AC-10) ---


def gcs_settings() -> Settings:
    return Settings(wardrobe_storage="gcs", wardrobe_gcs_bucket="test-bucket")


def test_agent_tools_read_clothes_from_gcs(monkeypatch: pytest.MonkeyPatch) -> None:
    """AC-9: Cloud Storage のとき、エージェントのツールはバケットの index.json を読む。"""
    bucket = FakeBucket()
    store = make_store(bucket)
    store.add(JPEG, "image/jpeg", [cloth("Tシャツ"), cloth("パーカー", colors=["黒"])], "", "m")
    monkeypatch.setattr(
        "app.services.wardrobe.create_wardrobe_store", lambda settings: make_store(bucket)
    )

    list_wardrobe, search_wardrobe = build_wardrobe_tools(gcs_settings())

    listed = list_wardrobe()
    assert listed["count"] == 2
    assert listed["items"][0]["image"].startswith("cloth-")
    assert "id" not in listed["items"][0]
    assert [i["category"] for i in search_wardrobe("黒")["items"]] == ["パーカー"]


def test_agent_tools_report_empty_bucket(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.services.wardrobe.create_wardrobe_store", lambda settings: make_store(FakeBucket())
    )

    result = build_wardrobe_tools(gcs_settings())[0]()

    assert result["status"] == "error"
    assert "gs://test-bucket/wardrobe/index.json" in result["message"]


def test_agent_tools_report_unreadable_bucket(monkeypatch: pytest.MonkeyPatch) -> None:
    """読めないときも例外にせず、エージェントが説明できるよう status=error を返す。"""
    from google.api_core.exceptions import Forbidden

    bucket = FakeBucket(fail_with=Forbidden("denied"))
    monkeypatch.setattr(
        "app.services.wardrobe.create_wardrobe_store", lambda settings: make_store(bucket)
    )

    result = build_wardrobe_tools(gcs_settings())[1]("白")

    assert result["status"] == "error"
    assert "読み込めませんでした" in result["message"]


def test_agent_tools_use_local_file_by_default(tmp_path: Path) -> None:
    """AC-10: 既定(local)では、今までどおりローカルの index.json を読む。"""
    local = LocalWardrobeStore(tmp_path / "index.json")
    local.add(JPEG, "image/jpeg", [cloth("Tシャツ")], "", "m")

    result = build_wardrobe_tools(Settings(cloth_index_path=str(local.index_file)))[0]()

    assert result["count"] == 1


# --- 失敗時(AC-6) ---


def test_connection_errors_become_store_errors() -> None:
    """AC-6: 接続できない・権限が無いときは WardrobeStoreError になる。"""
    from google.api_core.exceptions import Forbidden

    bucket = FakeBucket(fail_with=Forbidden("denied"))
    store = make_store(bucket)

    with pytest.raises(WardrobeStoreError, match="Forbidden"):
        store.list_entries()
    with pytest.raises(WardrobeStoreError):
        add(store, "Tシャツ")
    with pytest.raises(WardrobeStoreError):
        store.read_image("cloth-1.jpg")
    with pytest.raises(WardrobeStoreError):
        store.delete_item("x")


def test_broken_index_becomes_store_error() -> None:
    bucket = FakeBucket()
    bucket._put(INDEX, b"{broken", "application/json")

    with pytest.raises(WardrobeStoreError, match="gs://test-bucket/wardrobe/index.json"):
        make_store(bucket).list_entries()


def test_index_failure_removes_uploaded_photo() -> None:
    """index.json の書き込みに失敗したら、一覧に載らない写真を残さない。"""
    bucket = FakeBucket()
    bucket._put(INDEX, b"{broken", "application/json")

    with pytest.raises(WardrobeStoreError):
        add(make_store(bucket), "Tシャツ")
    assert list(bucket.objects) == [INDEX]


def test_missing_bucket_name_is_store_error() -> None:
    """バケット名が未設定でも、作るときではなく使うときにエラーにする(起動を止めない)。"""
    store = GcsWardrobeStore("", prefix="wardrobe")

    with pytest.raises(WardrobeStoreError, match="WARDROBE_GCS_BUCKET"):
        store.list_entries()
