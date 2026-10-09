"""持ち主(ユーザー・ゲスト)ごとの手持ちの服の置き場所(spec 038)のテスト。"""

import json
from datetime import datetime, timedelta
from pathlib import Path

import pytest

from app.core.config import Settings
from app.services.auth import Owner
from app.services.cloth_index import ClothItem
from app.services.wardrobe_gcs import GcsWardrobeStore
from app.services.wardrobe_store import (
    LocalWardrobeStore,
    WardrobeStoreError,
    create_wardrobe_store,
    describe_wardrobe_location,
    owner_prefix,
)
from tests.gcs_stub import FakeBucket

JPEG = b"\xff\xd8\xff\xe0jpeg-data"
USER_A = Owner(kind="user", id="demo01")
USER_B = Owner(kind="user", id="demo02")
GUEST = Owner(kind="guest", id="0123456789abcdef0123456789abcdef")


def cloth(category: str) -> ClothItem:
    return ClothItem(category=category, material="綿", shape="半袖")


def local_settings(tmp_path: Path) -> Settings:
    return Settings(wardrobe_local_root=str(tmp_path), guest_wardrobe_hours=24)


def test_owner_prefix_separates_users_and_guests() -> None:
    assert owner_prefix(USER_A) == "users/demo01/wardrobe"
    assert owner_prefix(GUEST) == f"guests/{GUEST.id}/wardrobe"


@pytest.mark.parametrize("bad_id", ["..", "../x", "a/b", "A"])
def test_owner_prefix_rejects_path_like_ids(bad_id: str) -> None:
    with pytest.raises(WardrobeStoreError):
        owner_prefix(Owner(kind="user", id=bad_id))


def test_local_store_is_separated_per_owner(tmp_path: Path) -> None:
    """AC-8・AC-9: ローカルでもユーザー A・B・ゲストの服が別のフォルダに分かれる。"""
    settings = local_settings(tmp_path)
    store_a = create_wardrobe_store(settings, USER_A)
    store_b = create_wardrobe_store(settings, USER_B)
    entry_a = store_a.add(JPEG, "image/jpeg", [cloth("Tシャツ")], "", "m")
    store_b.add(JPEG, "image/jpeg", [cloth("パンツ")], "", "m")

    assert isinstance(store_a, LocalWardrobeStore)
    assert store_a.index_file == tmp_path.resolve() / "users/demo01/wardrobe/index.json"
    assert [e.items[0].category for e in store_a.list_entries()] == ["Tシャツ"]
    assert [e.items[0].category for e in store_b.list_entries()] == ["パンツ"]
    assert create_wardrobe_store(settings, GUEST).list_entries() == []
    # B から A の写真・服は見えない
    assert store_b.read_image(entry_a.image) is None
    assert store_b.delete_item(entry_a.items[0].id) is False


def test_gcs_store_is_separated_per_owner() -> None:
    """AC-9: Cloud Storage では users/<ID>/wardrobe/ と guests/<番号>/wardrobe/ に分かれる。"""
    settings = Settings(wardrobe_storage="gcs", wardrobe_gcs_bucket="b")
    bucket = FakeBucket()

    def store(owner: Owner) -> GcsWardrobeStore:
        created = create_wardrobe_store(settings, owner)
        assert isinstance(created, GcsWardrobeStore)
        created._bucket = bucket  # type: ignore[assignment]
        return created

    entry = store(USER_A).add(JPEG, "image/jpeg", [cloth("Tシャツ")], "", "m")
    store(GUEST).add(JPEG, "image/jpeg", [cloth("パンツ")], "", "m")

    assert "users/demo01/wardrobe/index.json" in bucket.objects
    assert f"users/demo01/wardrobe/images/{entry.image}" in bucket.objects
    assert f"guests/{GUEST.id}/wardrobe/index.json" in bucket.objects
    assert store(USER_B).list_entries() == []
    assert store(USER_B).read_image(entry.image) is None
    assert describe_wardrobe_location(settings, USER_A) == "gs://b/users/demo01/wardrobe/index.json"


def test_without_owner_keeps_previous_location(tmp_path: Path) -> None:
    """持ち主を渡さなければ、今までどおりの置き場所(CLI のエージェントの既定)。"""
    settings = Settings(cloth_index_path=str(tmp_path / "wardrobe" / "index.json"))

    store = create_wardrobe_store(settings)

    assert isinstance(store, LocalWardrobeStore)
    assert store.index_file == tmp_path / "wardrobe" / "index.json"
    assert store.max_age is None


def _write_index(path: Path, analyzed_at: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    entries = [
        {
            "image": f"cloth-{i}.jpg",
            "items": [{"id": f"id{i}", **cloth(f"服{i}").model_dump()}],
            "analyzed_at": at,
        }
        for i, at in enumerate(analyzed_at)
    ]
    path.write_text(json.dumps({"entries": entries}, ensure_ascii=False), encoding="utf-8")


def test_guest_clothes_older_than_limit_are_hidden(tmp_path: Path) -> None:
    """AC-6・AC-7: ゲストは 24 時間より古い服を読まない。ユーザーは古くても残る。"""
    settings = local_settings(tmp_path)
    now = datetime.now().astimezone()
    times = [
        (now - timedelta(hours=25)).isoformat(timespec="seconds"),
        (now - timedelta(hours=1)).isoformat(timespec="seconds"),
    ]
    guest_store = create_wardrobe_store(settings, GUEST)
    user_store = create_wardrobe_store(settings, USER_A)
    assert isinstance(guest_store, LocalWardrobeStore)
    assert isinstance(user_store, LocalWardrobeStore)
    _write_index(guest_store.index_file, times)
    _write_index(user_store.index_file, times)

    assert [e.image for e in guest_store.list_entries()] == ["cloth-1.jpg"]
    assert len(user_store.list_entries()) == 2

    # 書き戻すと、古い服はゲストの index.json からも消える
    guest_store.add(JPEG, "image/jpeg", [cloth("新しい服")], "", "m")
    saved = json.loads(guest_store.index_file.read_text(encoding="utf-8"))
    assert [e["image"] for e in saved["entries"]][0] == "cloth-1.jpg"
    assert len(saved["entries"]) == 2


def test_guest_expiry_applies_to_gcs() -> None:
    bucket = FakeBucket()
    store = GcsWardrobeStore(
        "b",
        prefix=owner_prefix(GUEST),
        bucket=bucket,
        max_age=timedelta(hours=24),  # type: ignore[arg-type]
    )
    old = (datetime.now().astimezone() - timedelta(days=2)).isoformat(timespec="seconds")
    entries = [{"image": "cloth-old.jpg", "items": [], "analyzed_at": old}]
    bucket._put(
        f"{owner_prefix(GUEST)}/index.json",
        json.dumps({"entries": entries}).encode(),
        "application/json",
    )

    assert store.list_entries() == []
