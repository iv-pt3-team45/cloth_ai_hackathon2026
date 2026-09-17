"""エージェントをターミナルから単体で動かすスクリプト。

サーバもフロントも起動せず、このファイルを実行するだけでエージェントと会話できる。
画像・動画を添付して渡すこともできる。

使い方(backend/ をカレントにして実行):

    # 対話モード
    uv run python scripts/run_agent.py

    # 単発実行
    uv run python scripts/run_agent.py -m "こんにちは"

    # 画像を添付して単発実行
    uv run python scripts/run_agent.py -m "この画像を説明して" -f path/to/photo.png

    # 手持ちの服(index.json)を踏まえて答えさせる
    uv run python scripts/run_agent.py -m "手持ちの服で今日のコーデを考えて"

    # Cloud Storage の動画を渡す(ダウンロードしない)
    uv run python scripts/run_agent.py -m "この動画を要約して" -f gs://bucket/movie.mp4

対話モード中のコマンド:

    /file <パス|gs://...>   次のメッセージに添付する
    /files                  添付予定の一覧
    /clear                  添付予定を取り消す
    /reset                  会話履歴を消す
    /help                   ヘルプ
    /exit                   終了
"""

import argparse
import asyncio
import logging
import sys
from pathlib import Path

# `uv run python scripts/run_agent.py` のように直接実行しても app パッケージを解決できるようにする
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import get_settings  # noqa: E402
from app.schemas.chat import Attachment, ChatMessage  # noqa: E402
from app.services.agent import AgentError, AgentService  # noqa: E402
from app.services.attachments import AttachmentError, load_attachment  # noqa: E402

PROMPT = "\nあなた> "
HELP = """\
コマンド一覧:
  /file <パス|gs://...>   次のメッセージに添付する(画像・動画)
  /files                  添付予定の一覧
  /clear                  添付予定を取り消す
  /reset                  会話履歴を消す
  /help                   このヘルプ
  /exit                   終了(Ctrl+C でも可)
"""


def configure_console() -> None:
    """Windows のコンソールでも日本語が化けないよう UTF-8 に揃える。"""
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def describe(attachment: Attachment) -> str:
    """添付を 1 行で表示する文字列にする。"""
    if attachment.uri:
        return f"{attachment.uri} ({attachment.mime_type})"
    size_kb = len(attachment.data or "") * 3 / 4 / 1024
    return f"<inline {size_kb:.1f} KB> ({attachment.mime_type})"


async def ask(
    service: AgentService,
    message: str,
    history: list[ChatMessage],
    attachments: list[Attachment],
) -> str | None:
    """1 往復ぶんの問い合わせ。失敗したらエラーを表示して None を返す。"""
    try:
        return await service.generate_reply(message, history, attachments)
    except AgentError as exc:
        print(f"\n[エラー] {exc}", file=sys.stderr)
        return None


async def run_once(service: AgentService, message: str, paths: list[str]) -> int:
    """単発実行モード。終了コードを返す。"""
    try:
        attachments = [load_attachment(p) for p in paths]
    except AttachmentError as exc:
        print(f"[エラー] {exc}", file=sys.stderr)
        return 1

    reply = await ask(service, message, [], attachments)
    if reply is None:
        return 1
    print(reply)
    return 0


async def run_interactive(service: AgentService, paths: list[str]) -> int:
    """対話モード。履歴を保持しながら会話を続ける。"""
    settings = service.settings
    history: list[ChatMessage] = []
    pending: list[Attachment] = []

    for path in paths:
        try:
            pending.append(load_attachment(path))
        except AttachmentError as exc:
            print(f"[エラー] {exc}", file=sys.stderr)
            return 1

    print(f"モデル: {settings.gemini_model} / プロジェクト: {settings.google_cloud_project}")
    print("/help でコマンド一覧、/exit で終了します。")

    while True:
        try:
            # 入力待ちでイベントループを止めないよう別スレッドで受ける
            line = (await asyncio.to_thread(input, PROMPT)).strip()
        except (EOFError, KeyboardInterrupt):
            print("\n終了します。")
            return 0

        if not line:
            continue

        if line.startswith("/"):
            command, _, argument = line.partition(" ")
            argument = argument.strip()

            if command in ("/exit", "/quit"):
                print("終了します。")
                return 0
            if command == "/help":
                print(HELP)
            elif command == "/reset":
                history.clear()
                print("会話履歴を消しました。")
            elif command == "/clear":
                pending.clear()
                print("添付予定を取り消しました。")
            elif command == "/files":
                if not pending:
                    print("添付予定はありません。")
                for index, attachment in enumerate(pending, start=1):
                    print(f"  {index}. {describe(attachment)}")
            elif command == "/file":
                if not argument:
                    print("使い方: /file <パス|gs://...>")
                    continue
                try:
                    attachment = load_attachment(argument)
                except AttachmentError as exc:
                    print(f"[エラー] {exc}", file=sys.stderr)
                    continue
                pending.append(attachment)
                print(f"添付しました: {describe(attachment)}")
            else:
                print(f"不明なコマンドです: {command}(/help でヘルプ)")
            continue

        reply = await ask(service, line, history, pending)
        if reply is None:
            continue

        print(f"\nエージェント> {reply}")
        history.append(ChatMessage(role="user", content=line))
        history.append(ChatMessage(role="model", content=reply))
        pending.clear()


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="ADK エージェントをターミナルから動かす",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=HELP,
    )
    parser.add_argument("-m", "--message", help="単発実行するメッセージ(省略時は対話モード)")
    parser.add_argument(
        "-f",
        "--file",
        action="append",
        default=[],
        metavar="PATH",
        help="添付する画像・動画。ローカルパスまたは gs:// URI。複数指定可",
    )
    parser.add_argument("--model", help="GEMINI_MODEL を一時的に上書きする")
    parser.add_argument("--index", help="参照する服インデックス(index.json)のパス")
    parser.add_argument("-v", "--verbose", action="store_true", help="ライブラリのログも表示する")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    configure_console()
    args = parse_args(argv)

    # 既定ではライブラリのスタックトレースを抑える(失敗内容はエージェントの応答に出る)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.CRITICAL)

    settings = get_settings()
    overrides: dict[str, str] = {}
    if args.model:
        overrides["gemini_model"] = args.model
    if args.index:
        overrides["cloth_index_path"] = args.index

    # 設定を差し替えるときだけ AgentService に渡す(既定は共有 Runner を使う)
    if overrides:
        settings = settings.model_copy(update=overrides)
        service = AgentService(settings)
    else:
        service = AgentService()

    try:
        if args.message:
            return asyncio.run(run_once(service, args.message, args.file))
        return asyncio.run(run_interactive(service, args.file))
    except KeyboardInterrupt:
        print("\n終了します。")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
