"""ログインとゲストの通行証(spec 038)のテスト。外部サービスは呼ばない。"""

from datetime import UTC, datetime, timedelta
from pathlib import Path

import jwt
import pytest

from app.core.config import Settings
from app.services.auth import (
    AuthConfigError,
    AuthService,
    InvalidCredentialsError,
    InvalidTokenError,
    Owner,
    decode_token,
    hash_password,
    issue_token,
    verify_password,
)
from app.services.user_store import LocalUserStore, create_user_store
from app.services.user_store_gcs import GcsUserStore
from tests.gcs_stub import FakeBucket

NOW = datetime(2026, 10, 9, 12, 0, tzinfo=UTC)
SECRET = "test-secret-key-0123456789abcdef"
GUEST_ID = "0123456789abcdef0123456789abcdef"


def make_settings(tmp_path: Path, **overrides: object) -> Settings:
    values: dict[str, object] = {
        "wardrobe_local_root": str(tmp_path),
        "auth_secret_key": SECRET,
        "auth_token_days": 7,
    }
    values.update(overrides)
    return Settings(**values)  # type: ignore[arg-type]


def make_service(tmp_path: Path, **overrides: object) -> tuple[AuthService, LocalUserStore]:
    settings = make_settings(tmp_path, **overrides)
    users = LocalUserStore(tmp_path / "auth" / "users.json")
    return AuthService(settings, users=users), users


# --- パスワード(AC-3) ---


def test_password_hash_is_salted_and_verifiable() -> None:
    first = hash_password("secret-pass")
    second = hash_password("secret-pass")

    assert first != second  # ソルトが毎回違う
    assert "secret-pass" not in first
    assert first.startswith("scrypt$")
    assert verify_password("secret-pass", first)
    assert not verify_password("wrong", first)


def test_verify_password_rejects_broken_hash() -> None:
    assert not verify_password("x", "")
    assert not verify_password("x", "plain-text")
    assert not verify_password("x", "bcrypt$1$2$3$4$5")


# --- トークン(AC-10) ---


def test_token_round_trip() -> None:
    owner = Owner(kind="user", id="demo01")
    issued = issue_token(owner, SECRET, NOW, days=7)

    assert issued.expires_at == NOW + timedelta(days=7)
    assert decode_token(issued.token, SECRET, NOW + timedelta(days=6)) == owner


def test_expired_token_is_rejected() -> None:
    issued = issue_token(Owner(kind="guest", id=GUEST_ID), SECRET, NOW, days=7)

    with pytest.raises(InvalidTokenError, match="期限"):
        decode_token(issued.token, SECRET, NOW + timedelta(days=7))


def test_tampered_token_is_rejected() -> None:
    issued = issue_token(Owner(kind="user", id="demo01"), SECRET, NOW, days=7)

    with pytest.raises(InvalidTokenError):
        decode_token(issued.token, "another-secret-key-0123456789abc", NOW)
    with pytest.raises(InvalidTokenError):
        decode_token(issued.token[:-2] + "xx", SECRET, NOW)
    with pytest.raises(InvalidTokenError):
        decode_token("not-a-token", SECRET, NOW)


@pytest.mark.parametrize(
    ("kind", "sub"),
    [
        ("admin", "demo01"),
        ("user", "../etc"),
        ("user", "A"),
        ("guest", "not-hex"),
        ("guest", "demo01"),
    ],
)
def test_token_with_unexpected_content_is_rejected(kind: str, sub: str) -> None:
    """署名が正しくても、種類や ID の形式が違えば受け付けない(置き場所の外を指させない)。"""
    exp = int((NOW + timedelta(days=1)).timestamp())
    token = jwt.encode(
        {"sub": sub, "kind": kind, "iat": int(NOW.timestamp()), "exp": exp},
        SECRET,
        algorithm="HS256",
    )

    with pytest.raises(InvalidTokenError):
        decode_token(token, SECRET, NOW)


def test_unsigned_token_is_rejected() -> None:
    payload = {"sub": "demo01", "kind": "user", "iat": 0, "exp": 2**40}
    token = jwt.encode(payload, key=None, algorithm="none")  # type: ignore[arg-type]

    with pytest.raises(InvalidTokenError):
        decode_token(token, SECRET, NOW)


# --- ログイン(AC-1・AC-2・AC-15) ---


def test_login_with_registered_user(tmp_path: Path) -> None:
    service, users = make_service(tmp_path)
    users.set_password("demo01", hash_password("pass-01"))

    issued = service.login("demo01", "pass-01", now=NOW)

    assert issued.owner == Owner(kind="user", id="demo01")
    assert service.owner_from_token(issued.token, now=NOW) == issued.owner


@pytest.mark.parametrize(("user_id", "password"), [("demo01", "wrong"), ("nobody", "pass-01")])
def test_login_failure_does_not_reveal_which_is_wrong(
    tmp_path: Path, user_id: str, password: str
) -> None:
    service, users = make_service(tmp_path)
    users.set_password("demo01", hash_password("pass-01"))

    with pytest.raises(InvalidCredentialsError, match="ユーザー ID またはパスワードが違います"):
        service.login(user_id, password, now=NOW)


def test_login_rejects_invalid_user_id_format(tmp_path: Path) -> None:
    service, _ = make_service(tmp_path)

    with pytest.raises(InvalidCredentialsError):
        service.login("../../etc", "x", now=NOW)


def test_user_changes_take_effect_immediately(tmp_path: Path) -> None:
    """AC-15: パスワード変更・削除が、再起動なしで反映される。"""
    service, users = make_service(tmp_path)
    users.set_password("demo01", hash_password("old"))
    issued = service.login("demo01", "old", now=NOW)

    users.set_password("demo01", hash_password("new"))
    with pytest.raises(InvalidCredentialsError):
        service.login("demo01", "old", now=NOW)
    assert service.login("demo01", "new", now=NOW)

    assert users.delete("demo01") is True
    # 削除したユーザーのトークンは使えない
    with pytest.raises(InvalidTokenError):
        service.owner_from_token(issued.token, now=NOW)


def test_users_file_does_not_contain_plain_password(tmp_path: Path) -> None:
    """AC-3"""
    _, users = make_service(tmp_path)
    users.set_password("demo01", hash_password("very-secret-pass"))

    text = (tmp_path / "auth" / "users.json").read_text(encoding="utf-8")
    assert "very-secret-pass" not in text
    assert "scrypt$" in text


# --- ゲスト ---


def test_guest_token_has_random_id(tmp_path: Path) -> None:
    service, _ = make_service(tmp_path)

    first = service.guest(now=NOW)
    second = service.guest(now=NOW)

    assert first.owner.kind == "guest"
    assert first.owner.id != second.owner.id
    assert len(first.owner.id) == 32
    assert service.owner_from_token(first.token, now=NOW) == first.owner


# --- 署名の鍵 ---


def test_missing_secret_outside_local_is_config_error(tmp_path: Path) -> None:
    service, _ = make_service(tmp_path, auth_secret_key="", environment="prod")

    with pytest.raises(AuthConfigError, match="AUTH_SECRET_KEY"):
        service.guest(now=NOW)


def test_missing_secret_in_local_uses_ephemeral_key(tmp_path: Path) -> None:
    service, _ = make_service(tmp_path, auth_secret_key="", environment="local")

    issued = service.guest(now=NOW)

    assert service.owner_from_token(issued.token, now=NOW) == issued.owner


# --- ユーザーの保存先 ---


def test_user_store_follows_storage_setting(tmp_path: Path) -> None:
    local = create_user_store(make_settings(tmp_path))
    assert isinstance(local, LocalUserStore)
    assert local.path == tmp_path.resolve() / "auth" / "users.json"

    gcs = create_user_store(
        make_settings(tmp_path, wardrobe_storage="gcs", wardrobe_gcs_bucket="b")
    )
    assert isinstance(gcs, GcsUserStore)


def test_gcs_user_store_add_change_delete() -> None:
    bucket = FakeBucket()
    store = GcsUserStore("b", bucket=bucket)  # type: ignore[arg-type]

    assert store.set_password("demo01", hash_password("a")) is True
    assert store.set_password("demo01", hash_password("b")) is False
    assert store.set_password("demo02", hash_password("c")) is True

    reloaded = GcsUserStore("b", bucket=bucket)  # type: ignore[arg-type]
    assert reloaded.list_ids() == ["demo01", "demo02"]
    record = reloaded.get("demo01")
    assert record is not None and verify_password("b", record.password)
    assert "auth/users.json" in bucket.objects

    assert reloaded.delete("demo01") is True
    assert reloaded.delete("demo01") is False
    assert reloaded.list_ids() == ["demo02"]


def test_gcs_user_store_keeps_concurrent_additions() -> None:
    bucket = FakeBucket()
    store = GcsUserStore("b", bucket=bucket)  # type: ignore[arg-type]
    other = GcsUserStore("b", bucket=bucket)  # type: ignore[arg-type]
    bucket.before_upload = lambda name: other.set_password("demo02", "h2") and None

    store.set_password("demo01", "h1")

    assert GcsUserStore("b", bucket=bucket).list_ids() == ["demo01", "demo02"]  # type: ignore[arg-type]
