"""服の画像から属性を抽出してインデックス(JSON)を作るスクリプト。

画像 1 枚ごとに素材・形・色・系統などを抽出し、
画像ごとの JSON と全体の `index.json` を出力先に保存する。

使い方(backend/ をカレントにして実行):

    # 既定(tests/sample_images → tests/sample_cloth_indexs)
    uv run python scripts/build_cloth_index.py

    # ディレクトリを指定
    uv run python scripts/build_cloth_index.py -i path/to/images -o path/to/index

    # 処理済みも作り直す
    uv run python scripts/build_cloth_index.py --force
"""

import argparse
import logging
import sys
from pathlib import Path

# 直接実行しても app パッケージを解決できるようにする
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import get_settings  # noqa: E402
from app.services.cloth_index import (  # noqa: E402
    INDEX_FILE_NAME,
    ClothIndexEntry,
    ClothIndexError,
    build_cloth_index,
)

DEFAULT_SOURCE = Path("tests/sample_images")
DEFAULT_OUTPUT = Path("tests/sample_cloth_indexs")

_STATUS_LABEL = {"analyzed": "解析", "skipped": "スキップ", "failed": "失敗"}


def configure_console() -> None:
    """Windows のコンソールでも日本語が化けないよう UTF-8 に揃える。"""
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def print_progress(image: Path, entry: ClothIndexEntry | None, status: str) -> None:
    """1 枚ぶんの経過を表示する。"""
    label = _STATUS_LABEL.get(status, status)
    if entry is None:
        print(f"  [{label}] {image.name}")
        return

    summary = "、".join(
        f"{item.category}({'/'.join(item.colors) or '色不明'}・{item.material}・{item.style})"
        for item in entry.items
    )
    print(f"  [{label}] {image.name} → {summary or '衣類なし'}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="服画像のインデックスを作成する")
    parser.add_argument("-i", "--input", type=Path, default=DEFAULT_SOURCE, help="画像ディレクトリ")
    parser.add_argument("-o", "--output", type=Path, default=DEFAULT_OUTPUT, help="JSON の出力先")
    parser.add_argument("--force", action="store_true", help="処理済みの画像も作り直す")
    parser.add_argument("-v", "--verbose", action="store_true", help="ライブラリのログも表示する")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    configure_console()
    args = parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.WARNING)

    settings = get_settings()
    print(f"画像: {args.input}")
    print(f"出力: {args.output}")
    print(f"モデル: {settings.cloth_index_model}")

    try:
        entries = build_cloth_index(
            args.input, args.output, force=args.force, on_progress=print_progress
        )
    except ClothIndexError as exc:
        print(f"[エラー] {exc}", file=sys.stderr)
        return 1

    total_items = sum(len(entry.items) for entry in entries)
    print(f"\n完了: 画像 {len(entries)} 件 / 衣類 {total_items} 件")
    print(f"一覧: {args.output / INDEX_FILE_NAME}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
