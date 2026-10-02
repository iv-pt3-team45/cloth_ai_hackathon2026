"""服インデックス作成のテスト(外部 API は呼ばない)。"""

import json
from collections.abc import Callable
from pathlib import Path
from types import SimpleNamespace
from typing import Any

from google.genai import types

from app.core.config import Settings
from app.services.cloth_index import (
    INDEX_FILE_NAME,
    ClothAnalysis,
    ClothIndexEntry,
    ClothIndexError,
    ClothItem,
    analyze_cloth_bytes,
    build_cloth_index,
    guess_mime_type,
    index_path,
    list_images,
    load_index,
    normalize_item,
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


# --- spec 010: 季節・暖かさ・使う場面と、画像データでの解析 -------------------


def test_normalize_item_keeps_only_choices() -> None:
    """選択肢の外の値は捨て、選択肢の順に並べる。説明つきの値は先頭の語で照合する。"""
    item = ClothItem(
        category="コート",
        material="ウール",
        shape="ロング",
        seasons=["冬", "春", "夏季", "春"],
        warmth="やや厚手",
        occasions=["ライブ・フェス", "きれいめ(食事・オフィス)", "デート"],
    )

    normalized = normalize_item(item)

    assert normalized.seasons == ["春", "冬"]
    assert normalized.warmth == ""
    assert normalized.occasions == ["きれいめ", "ライブ・フェス"]
    assert normalize_item(item.model_copy(update={"warmth": "厚手"})).warmth == "厚手"


def test_old_index_without_new_fields_is_readable(tmp_path: Path) -> None:
    """項目の無い既存の index.json(spec 005)も既定値で読める。"""
    index_path(tmp_path).write_text(
        json.dumps(
            {
                "entries": [
                    {
                        "image": "a.jpg",
                        "items": [{"category": "Tシャツ", "material": "綿", "shape": "半袖"}],
                    }
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    item = load_index(tmp_path)["a.jpg"].items[0]

    assert (item.seasons, item.warmth, item.occasions) == ([], "", [])


def fake_client(respond: Callable[..., Any]) -> Any:
    calls: list[dict[str, Any]] = []

    def generate_content(**kwargs: Any) -> Any:
        calls.append(kwargs)
        return respond(**kwargs)

    return SimpleNamespace(models=SimpleNamespace(generate_content=generate_content), calls=calls)


def test_analyze_cloth_bytes_normalizes_result() -> None:
    raw = ClothAnalysis(
        items=[
            ClothItem(
                category="Tシャツ",
                material="綿",
                shape="半袖",
                seasons=["夏", "真夏"],
                warmth="薄手",
                occasions=["普段着", "ライブ・フェス(屋外)"],
            )
        ],
        summary="白い T シャツ",
    )
    client = fake_client(lambda **kwargs: types.GenerateContentResponse(parsed=raw))

    analysis = analyze_cloth_bytes(
        b"\xff\xd8\xffdata", "image/jpeg", settings=Settings(), client=client
    )

    item = analysis.items[0]
    assert (item.seasons, item.warmth, item.occasions) == (
        ["夏"],
        "薄手",
        ["普段着", "ライブ・フェス"],
    )
    call = client.calls[0]
    image_part = call["contents"][0].parts[0]
    assert image_part.inline_data.mime_type == "image/jpeg"
    assert call["config"].response_schema is ClothAnalysis
    assert call["config"].automatic_function_calling.disable is True


def test_analyze_cloth_bytes_keeps_cause_of_failure() -> None:
    """呼び出し側がクォータ超過などを判定できるよう、元の例外を __cause__ に残す。"""
    original = RuntimeError("quota")

    def fail(**kwargs: Any) -> Any:
        raise original

    try:
        analyze_cloth_bytes(b"x", "image/png", settings=Settings(), client=fake_client(fail))
    except ClothIndexError as exc:
        assert exc.__cause__ is original
    else:  # pragma: no cover - 失敗時のみ
        raise AssertionError("ClothIndexError が送出されるべき")


def test_analyze_cloth_bytes_rejects_unreadable_response() -> None:
    client = fake_client(lambda **kwargs: types.GenerateContentResponse(parsed=None))

    try:
        analyze_cloth_bytes(b"x", "image/png", settings=Settings(), client=client)
    except ClothIndexError as exc:
        assert "解釈" in str(exc)
    else:  # pragma: no cover - 失敗時のみ
        raise AssertionError("ClothIndexError が送出されるべき")
