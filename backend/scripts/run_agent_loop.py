"""エージェントループを実行するスクリプト(生成 → 検証 → 未達なら再生成)。

対話はしない。要望を 1 つ渡すと、それを満たすまでエージェントが自動で試行を繰り返す。
対話したい場合は `run_agent.py` を使う。

使い方(backend/ をカレントにして実行):

    # 要望を満たすまで最大 3 周(既定)
    uv run python scripts/run_agent_loop.py -m "夕焼けの海辺にいる柴犬の画像を作って"

    # 上限を変える
    uv run python scripts/run_agent_loop.py -m "雪山の風景画像" -n 5

    # 手持ちの服を踏まえた要望
    uv run python scripts/run_agent_loop.py -m "手持ちの服を使った春コーデの画像を作って"

    # 参考画像を渡して始める
    uv run python scripts/run_agent_loop.py -m "この写真に似た雰囲気の画像を作って" -f sample.png

    # 生成モデル / 検証モデルを差し替える
    uv run python scripts/run_agent_loop.py -m "..." --verifier-model gemini-2.5-flash

終了コード: 要望を満たしたら 0、上限まで未達なら 1。
"""

import argparse
import asyncio
import logging
import sys
from pathlib import Path

# `uv run python scripts/run_agent_loop.py` のように直接実行しても app を解決できるようにする
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import get_settings  # noqa: E402
from app.schemas.chat import Attachment  # noqa: E402
from app.services.agent import AgentService  # noqa: E402
from app.services.agent_loop import LoopStep, run_agent_loop  # noqa: E402
from app.services.attachments import AttachmentError, load_attachment  # noqa: E402

SEPARATOR = "─" * 60


def configure_console() -> None:
    """Windows のコンソールでも日本語が化けないよう UTF-8 に揃える。"""
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def print_step(step: LoopStep) -> None:
    """1 周回の経過を表示する。"""
    print(f"\n{SEPARATOR}")
    print(f"[{step.iteration} 周目]")

    if step.error:
        print(f"  生成: 失敗 - {step.error}")
        return

    print(f"  生成: {step.reply.strip()[:300]}")
    print(f"  生成物: {step.artifact.name if step.artifact else '(なし)'}")

    if step.verdict is None:
        return

    mark = "満たした" if step.verdict.satisfied else "未達"
    print(f"  検証: {mark} - {step.verdict.reason.strip()[:300]}")
    if not step.verdict.satisfied and step.verdict.improvements.strip():
        print(f"  改善点: {step.verdict.improvements.strip()[:300]}")


def load_attachments(paths: list[str]) -> list[Attachment] | None:
    """添付を読み込む。失敗したら None を返す(呼び出し側で終了)。"""
    try:
        return [load_attachment(p) for p in paths]
    except AttachmentError as exc:
        print(f"[エラー] {exc}", file=sys.stderr)
        return None


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="要望を満たすまで生成と検証を繰り返すエージェントループ",
    )
    parser.add_argument("-m", "--message", required=True, help="達成したい要望")
    parser.add_argument("-n", "--max-iterations", type=int, help="繰り返しの上限(既定は設定値)")
    parser.add_argument(
        "-f",
        "--file",
        action="append",
        default=[],
        metavar="PATH",
        help="初回に渡す参考画像・動画。ローカルパスまたは gs:// URI",
    )
    parser.add_argument("--model", help="生成モデルを上書きする")
    parser.add_argument("--verifier-model", help="検証モデルを上書きする")
    parser.add_argument("--index", help="参照する服インデックス(index.json)のパス")
    parser.add_argument("-v", "--verbose", action="store_true", help="ライブラリのログも表示する")
    return parser.parse_args(argv)


async def run(args: argparse.Namespace) -> int:
    settings = get_settings()
    overrides: dict[str, str] = {}
    if args.model:
        overrides["gemini_model"] = args.model
    if args.verifier_model:
        overrides["verifier_model"] = args.verifier_model
    if args.index:
        overrides["cloth_index_path"] = args.index
    if overrides:
        settings = settings.model_copy(update=overrides)

    attachments = load_attachments(args.file)
    if attachments is None:
        return 1

    limit = args.max_iterations if args.max_iterations is not None else settings.loop_max_iterations
    print(f"要望: {args.message}")
    print(f"生成モデル: {settings.gemini_model} / 検証モデル: {settings.verifier_model}")
    print(f"上限: {limit} 周")

    result = await run_agent_loop(
        args.message,
        max_iterations=args.max_iterations,
        attachments=attachments,
        # 設定を差し替えた場合だけサービスにも反映する
        service=AgentService(settings) if overrides else None,
        settings=settings,
        on_step=print_step,
    )

    print(f"\n{SEPARATOR}")
    if result.satisfied:
        print(f"結果: 要望を満たしました({len(result.steps)} 周)")
    else:
        print(f"結果: {len(result.steps)} 周試しましたが要望を満たせませんでした")

    if result.final_artifact:
        print(f"最終成果物: {result.final_artifact}")
    return 0 if result.satisfied else 1


def main(argv: list[str] | None = None) -> int:
    configure_console()
    args = parse_args(argv)
    # 既定ではライブラリのスタックトレースを抑える(失敗内容はエージェントの応答に出る)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.CRITICAL)

    try:
        return asyncio.run(run(args))
    except KeyboardInterrupt:
        print("\n中断しました。")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
