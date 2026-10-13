"""運営用のユーザー管理 CLI とエージェントの --user(spec 038)のテスト。"""

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest

from app.core.config import Settings
from app.services.auth import hash_password, verify_password
from app.services.cloth_index import ClothItem
from app.services.user_store import LocalUserStore
from app.services.wardrobe import build_wardrobe_tools
from app.services.wardrobe_store import create_wardrobe_store
from tests.auth_stub import TEST_OWNER


def load_script() -> ModuleType:
    path = Path(__file__).resolve().parents[1] / "scripts" / "manage_users.py"
    spec = importlib.util.spec_from_file_location("manage_users", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["manage_users"] = module
    spec.loader.exec_module(module)
    return module


cli = load_script()


def run(store: LocalUserStore, argv: list[str], answers: list[str] | None = None) -> int:
    inputs = iter(answers or [])
    return int(cli.run(cli.parse_args(argv), store, ask=lambda _: next(inputs)))


@pytest.fixture
def store(tmp_path: Path) -> LocalUserStore:
    return LocalUserStore(tmp_path / "auth" / "users.json")


def test_add_with_typed_password(store: LocalUserStore) -> None:
    """AC-15: パスワードは入力欄で受け取り、ハッシュだけを保存する。"""
    assert run(store, ["add", "demo01"], ["pass-0001", "pass-0001"]) == 0

    record = store.get("demo01")
    assert record is not None
    assert verify_password("pass-0001", record.password)
    assert "pass-0001" not in store.path.read_text(encoding="utf-8")


def test_add_with_generated_password_prints_it_once(
    store: LocalUserStore, capsys: pytest.CaptureFixture[str]
) -> None:
    assert run(store, ["add", "demo01", "--generate"]) == 0

    out = capsys.readouterr().out
    password = out.split("パスワード: ")[1].strip()
    record = store.get("demo01")
    assert record is not None and verify_password(password, record.password)


@pytest.mark.parametrize("answers", [["short", "short"], ["pass-0001", "pass-0002"]])
def test_add_rejects_short_or_mismatched_password(
    store: LocalUserStore, answers: list[str]
) -> None:
    assert run(store, ["add", "demo01"], answers) == 1
    assert store.get("demo01") is None


def test_add_rejects_invalid_id_and_duplicates(store: LocalUserStore) -> None:
    assert run(store, ["add", "Bad/ID", "--generate"]) == 1
    assert run(store, ["add", "demo01", "--generate"]) == 0
    assert run(store, ["add", "demo01", "--generate"]) == 1


def test_passwd_and_delete(store: LocalUserStore, capsys: pytest.CaptureFixture[str]) -> None:
    store.set_password("demo01", hash_password("old-pass"))

    assert run(store, ["passwd", "demo01"], ["new-pass-1", "new-pass-1"]) == 0
    record = store.get("demo01")
    assert record is not None and verify_password("new-pass-1", record.password)

    assert run(store, ["list"]) == 0
    assert "demo01" in capsys.readouterr().out
    assert run(store, ["delete", "demo01"]) == 0
    assert run(store, ["delete", "demo01"]) == 1
    assert run(store, ["passwd", "demo01", "--generate"]) == 1


def test_password_is_not_accepted_as_argument() -> None:
    """パスワードを引数で渡す口は無い(シェルの履歴に残さない)。"""
    with pytest.raises(SystemExit):
        cli.parse_args(["add", "demo01", "--password", "x"])


def test_agent_tools_read_given_users_clothes(tmp_path: Path) -> None:
    """AC-16: --user(AGENT_WARDROBE_USER)で、そのユーザーの服をエージェントが読む。"""
    settings = Settings(wardrobe_local_root=str(tmp_path))
    create_wardrobe_store(settings, TEST_OWNER).add(
        b"\xff\xd8\xff",
        "image/jpeg",
        [ClothItem(category="Tシャツ", material="綿", shape="半袖")],
        "",
        "m",
    )

    list_wardrobe, _ = build_wardrobe_tools(
        settings.model_copy(update={"agent_wardrobe_user": TEST_OWNER.id})
    )
    result = list_wardrobe()
    assert result["status"] == "ok"
    assert result["items"][0]["category"] == "Tシャツ"

    other, _ = build_wardrobe_tools(settings.model_copy(update={"agent_wardrobe_user": "nobody"}))
    assert other()["status"] == "error"
