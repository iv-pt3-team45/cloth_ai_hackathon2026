"""ログインできるユーザーを管理する運営用の CLI(spec 038)。

保存先は `WARDROBE_STORAGE` に従う
(local: `data/auth/users.json` / gcs: バケットの `auth/users.json`)。
本番のユーザーを作るときは `WARDROBE_STORAGE=gcs` と `WARDROBE_GCS_BUCKET` を設定して実行する。

パスワードはコマンドの引数では受け取らない(シェルの履歴に残るため)。入力欄で入れるか、
`--generate` でランダムに作って 1 回だけ表示する。

使い方:
    uv run python scripts/manage_users.py list
    uv run python scripts/manage_users.py add demo01              # パスワードを入力する
    uv run python scripts/manage_users.py add demo01 --generate   # ランダムに作って表示する
    uv run python scripts/manage_users.py passwd demo01 [--generate]
    uv run python scripts/manage_users.py delete demo01
"""

import argparse
import getpass
import secrets
import sys
from collections.abc import Callable
from pathlib import Path

# scripts/ から app パッケージを import できるようにする
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import get_settings  # noqa: E402
from app.services.auth import USER_ID, hash_password  # noqa: E402
from app.services.user_store import UserStore, UserStoreError, create_user_store  # noqa: E402

MIN_PASSWORD_LENGTH = 8


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ログインできるユーザーを管理する(spec 038)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="ユーザー ID の一覧")
    for name, help_text in [("add", "ユーザーを追加する"), ("passwd", "パスワードを変える")]:
        command = sub.add_parser(name, help=help_text)
        command.add_argument("user_id")
        command.add_argument(
            "--generate", action="store_true", help="パスワードをランダムに作って表示する"
        )
    delete = sub.add_parser("delete", help="ユーザーを削除する")
    delete.add_argument("user_id")
    return parser.parse_args(argv)


def read_password(ask: Callable[[str], str] = getpass.getpass) -> str | None:
    """パスワードを 2 回入力してもらう。短い・一致しないときは None。"""
    password = ask("パスワード: ")
    if len(password) < MIN_PASSWORD_LENGTH:
        print(f"パスワードは {MIN_PASSWORD_LENGTH} 文字以上にしてください。", file=sys.stderr)
        return None
    if ask("パスワード(確認): ") != password:
        print("パスワードが一致しません。", file=sys.stderr)
        return None
    return password


def generate_password() -> str:
    """ランダムなパスワード(英数字と - _ の 16 文字)。"""
    return secrets.token_urlsafe(12)


def run(
    args: argparse.Namespace,
    users: UserStore,
    ask: Callable[[str], str] = getpass.getpass,
) -> int:
    """コマンドを実行する。終了コードを返す。"""
    if args.command == "list":
        for listed in users.list_ids():
            print(listed)
        return 0

    user_id: str = args.user_id
    if not USER_ID.match(user_id):
        print("ユーザー ID は英小文字・数字・_・- の 3〜32 文字にしてください。", file=sys.stderr)
        return 1

    if args.command == "delete":
        if not users.delete(user_id):
            print(f"{user_id} は登録されていません。", file=sys.stderr)
            return 1
        print(f"{user_id} を削除しました。")
        return 0

    exists = users.get(user_id) is not None
    if args.command == "add" and exists:
        print(f"{user_id} は登録済みです。変えるときは passwd を使ってください。", file=sys.stderr)
        return 1
    if args.command == "passwd" and not exists:
        print(f"{user_id} は登録されていません。", file=sys.stderr)
        return 1

    password = generate_password() if args.generate else read_password(ask)
    if password is None:
        return 1
    users.set_password(user_id, hash_password(password))
    print(f"{user_id} を{'追加' if args.command == 'add' else '更新'}しました。")
    if args.generate:
        # 表示はこの 1 回だけ(保存するのはハッシュだけで、後から確かめる方法は無い)
        print(f"パスワード: {password}")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    settings = get_settings()
    where = (
        f"gs://{settings.wardrobe_gcs_bucket}/auth/users.json"
        if settings.wardrobe_storage == "gcs"
        else str(settings.wardrobe_local_root_path / "auth" / "users.json")
    )
    print(f"保存先: {where}", file=sys.stderr)
    try:
        return run(args, create_user_store(settings))
    except UserStoreError as exc:
        print(f"ユーザーの一覧を読み書きできませんでした: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
