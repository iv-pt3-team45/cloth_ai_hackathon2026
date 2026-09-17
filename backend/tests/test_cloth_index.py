"""服インデックス作成のテスト(外部 API は呼ばない)。"""

import json
from pathlib import Path

from app.services.cloth_index import (
    INDEX_FILE_NAME,
    ClothIndexEntry,
    ClothIndexError,
    ClothItem,
    build_cloth_index,
    guess_mime_type,
    index_path,
    list_images,
    load_index,
    save_index,
)


def make_entry(name: str) -> ClothIndexEntry:
    return ClothIndexEntry(
        image=name,
        items=[
            ClothItem(
                category="Tシャツ",
                material="綿",
                shape="半袖クルーネック",
                colors=["ピンク", "黄"],
                pattern="プリント",
                style="カジュアル",
                notes="胸に「Let's Eat」のロゴ",
            )
        ],
        summary="床に置かれたピンクのTシャツ",
        model="test-model",
        analyzed_at="2026-09-17T15:00:00+09:00",
    )


def test_list_images_ignores_non_images(tmp_path: Path) -> None:
    (tmp_path / "a.jpg").write_bytes(b"a")
    (tmp_path / "b.PNG").write_bytes(b"b")
    (tmp_path / "memo.txt").write_text("not an image", encoding="utf-8")
    (tmp_path / "sub").mkdir()

    names = [p.name for p in list_images(tmp_path)]

    assert names == ["a.jpg", "b.PNG"]


def test_list_images_reports_missing_directory(tmp_path: Path) -> None:
    try:
        list_images(tmp_path / "none")
    except ClothIndexError as exc:
        assert "ありません" in str(exc)
    else:  # pragma: no cover - 失敗時のみ
        raise AssertionError("ClothIndexError が送出されるべき")


def test_guess_mime_type() -> None:
    assert guess_mime_type(Path("a.JPEG")) == "image/jpeg"
    assert guess_mime_type(Path("a.png")) == "image/png"


def test_save_index_writes_single_file(tmp_path: Path) -> None:
    output = tmp_path / "out"

    path = save_index([make_entry("image.jpeg")], output, tmp_path / "src", "test-model")

    # 出力されるのは index.json だけ(画像ごとのファイルは作らない)
    assert path == index_path(output)
    assert [p.name for p in output.iterdir()] == [INDEX_FILE_NAME]

    saved = json.loads(path.read_text(encoding="utf-8"))
    assert saved["entries"][0]["items"][0]["material"] == "綿"
    assert saved["entries"][0]["items"][0]["colors"] == ["ピンク", "黄"]
    # 日本語がエスケープされずに保存される(人が読むため)
    assert "ピンク" in path.read_text(encoding="utf-8")


def test_load_index_returns_entries_by_image_name(tmp_path: Path) -> None:
    save_index([make_entry("a.jpg"), make_entry("b.jpg")], tmp_path, tmp_path, "test-model")

    known = load_index(tmp_path)

    assert set(known) == {"a.jpg", "b.jpg"}
    assert known["a.jpg"].items[0].category == "Tシャツ"


def test_load_index_returns_empty_for_missing_or_broken(tmp_path: Path) -> None:
    assert load_index(tmp_path) == {}

    index_path(tmp_path).write_text("{ broken", encoding="utf-8")
    assert load_index(tmp_path) == {}


def test_save_index_contains_all_entries(tmp_path: Path) -> None:
    entries = [make_entry("a.jpg"), make_entry("b.jpg")]

    path = save_index(entries, tmp_path, tmp_path / "src", "test-model")

    payload = json.loads(path.read_text(encoding="utf-8"))
    assert path.name == INDEX_FILE_NAME
    assert payload["count"] == 2
    assert [e["image"] for e in payload["entries"]] == ["a.jpg", "b.jpg"]


def test_build_cloth_index_analyzes_each_image(tmp_path: Path) -> None:
    source = tmp_path / "images"
    source.mkdir()
    for name in ("a.jpg", "b.jpg"):
        (source / name).write_bytes(b"x")
    output = tmp_path / "out"
    calls: list[Path] = []

    def fake_analyze(image: Path) -> ClothIndexEntry:
        calls.append(image)
        return make_entry(image.name)

    entries = build_cloth_index(source, output, analyze=fake_analyze)

    assert len(entries) == 2
    assert len(calls) == 2
    # 生成されるのは index.json 1 ファイルのみ
    assert [p.name for p in output.iterdir()] == [INDEX_FILE_NAME]


def test_build_cloth_index_skips_existing(tmp_path: Path) -> None:
    source = tmp_path / "images"
    source.mkdir()
    (source / "a.jpg").write_bytes(b"x")
    output = tmp_path / "out"
    calls: list[Path] = []

    def fake_analyze(image: Path) -> ClothIndexEntry:
        calls.append(image)
        return make_entry(image.name)

    build_cloth_index(source, output, analyze=fake_analyze)
    build_cloth_index(source, output, analyze=fake_analyze)

    assert len(calls) == 1  # 2 回目はスキップされる


def test_build_cloth_index_force_reanalyzes(tmp_path: Path) -> None:
    source = tmp_path / "images"
    source.mkdir()
    (source / "a.jpg").write_bytes(b"x")
    output = tmp_path / "out"
    calls: list[Path] = []

    def fake_analyze(image: Path) -> ClothIndexEntry:
        calls.append(image)
        return make_entry(image.name)

    build_cloth_index(source, output, analyze=fake_analyze)
    build_cloth_index(source, output, analyze=fake_analyze, force=True)

    assert len(calls) == 2


def test_build_cloth_index_continues_after_failure(tmp_path: Path) -> None:
    source = tmp_path / "images"
    source.mkdir()
    (source / "a.jpg").write_bytes(b"x")
    (source / "b.jpg").write_bytes(b"x")
    output = tmp_path / "out"
    statuses: list[str] = []

    def fake_analyze(image: Path) -> ClothIndexEntry:
        if image.name == "a.jpg":
            raise ClothIndexError("解析失敗")
        return make_entry(image.name)

    entries = build_cloth_index(
        source,
        output,
        analyze=fake_analyze,
        on_progress=lambda image, entry, status: statuses.append(status),
    )

    assert [e.image for e in entries] == ["b.jpg"]
    assert statuses == ["failed", "analyzed"]
