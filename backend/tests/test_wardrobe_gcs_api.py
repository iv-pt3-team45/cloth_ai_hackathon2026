"""保存先が Cloud Storage のときの API(spec 036)のテスト。Cloud Storage は偽物に差し替える。"""

from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient
from google.api_core.exceptions import Forbidden

from app.main import create_app
from app.services.outfit import OutfitService, get_outfit_service
from app.services.wardrobe_gcs import GcsWardrobeStore
from app.services.wardrobe_registry import WardrobeService, get_wardrobe_service
from tests.auth_stub import as_owner
from tests.gcs_stub import FakeBucket
from tests.outfit_stub import make_culture, make_live, make_video, unknown_venue
from tests.wardrobe_stub import fake_client, image_body, make_settings

ITEM = {
    "category": "Tシャツ",
    "material": "綿",
    "shape": "半袖",
    "colors": ["白"],
    "seasons": ["春", "夏"],
    "warmth": "薄手",
    "occasions": ["普段着"],
}


def gcs_store(bucket: FakeBucket) -> GcsWardrobeStore:
    return GcsWardrobeStore("test-bucket", bucket=bucket)  # type: ignore[arg-type]


def wardrobe_api(tmp_path: Path, bucket: FakeBucket) -> TestClient:
    service = WardrobeService(
        settings=make_settings(tmp_path), store=gcs_store(bucket), client=fake_client()
    )
    app = create_app()
    app.dependency_overrides[get_wardrobe_service] = lambda: service
    as_owner(app)
    return TestClient(app)


def test_register_list_image_delete_with_gcs(tmp_path: Path) -> None:
    """AC-2〜AC-4: API の形はそのままで、バケットに保存・一覧・写真・削除ができる。"""
    bucket = FakeBucket()
    api = wardrobe_api(tmp_path, bucket)

    res = api.post("/api/v1/wardrobe/items", json={"image": image_body(), "items": [ITEM]})
    assert res.status_code == 201
    item = res.json()["items"][0]
    assert "wardrobe/index.json" in bucket.objects
    # サーバー内のフォルダには何も書かない
    assert not (tmp_path / "wardrobe").exists()

    listed = api.get("/api/v1/wardrobe/items").json()
    assert listed["count"] == 1
    image = api.get(f"/api/v1/wardrobe/images/{item['image']}")
    assert image.status_code == 200
    assert image.headers["content-type"] == "image/jpeg"

    assert api.delete(f"/api/v1/wardrobe/items/{item['id']}").status_code == 204
    assert api.get("/api/v1/wardrobe/items").json()["count"] == 0
    assert list(bucket.objects) == ["wardrobe/index.json"]


def test_storage_failures_return_502(tmp_path: Path) -> None:
    """AC-6: 保存先を読み書きできないときは 502(アプリは落ちない)。"""
    api = wardrobe_api(tmp_path, FakeBucket(fail_with=Forbidden("denied")))

    assert api.get("/api/v1/wardrobe/items").status_code == 502
    assert api.get("/api/v1/wardrobe/images/cloth-1.jpg").status_code == 502
    res = api.post("/api/v1/wardrobe/items", json={"image": image_body(), "items": [ITEM]})
    assert res.status_code == 502
    assert api.delete("/api/v1/wardrobe/items/x").status_code == 502
    # 他の API は動き続ける
    assert api.get("/api/v1/health").status_code == 200


def test_outfit_returns_502_when_storage_fails(tmp_path: Path) -> None:
    """AC-6: コーデ提案も、保存先を読めなければ 502。"""
    service = OutfitService(
        settings=make_settings(tmp_path),
        store=gcs_store(FakeBucket(fail_with=Forbidden("denied"))),
        client=object(),  # type: ignore[arg-type]
        venue_lookup=unknown_venue,
    )
    app = create_app()
    app.dependency_overrides[get_outfit_service] = lambda: service
    as_owner(app)
    api = TestClient(app)
    body: dict[str, Any] = {
        "video": make_video().model_dump(mode="json"),
        "culture": make_culture().model_dump(mode="json"),
        "live": make_live().model_dump(mode="json"),
    }

    assert api.post("/api/v1/outfit/suggest", json=body).status_code == 502
    assert api.post("/api/v1/outfit/image", json={"item_ids": ["x"]}).status_code == 502
