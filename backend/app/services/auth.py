"""ログインとゲストの通行証(トークン)(spec 038)。

- ユーザー: 運営が事前に登録したユーザー(`user_store`)が、ID とパスワードでログインする。
- ゲスト: ログインしない人。サーバーがランダムなゲスト番号を発行する。

どちらもサーバーが署名したトークン(JWT、HS256)を渡し、サーバーは状態を覚えない。
トークンから分かる「持ち主」(`Owner`)ごとに、手持ちの服の置き場所を分ける。
"""

import base64
import hashlib
import hmac
import logging
import os
import re
import secrets
from datetime import UTC, datetime, timedelta
from typing import Literal

import jwt
from pydantic import BaseModel

from app.core.config import Settings, get_settings
from app.services.user_store import UserStore, UserStoreError, create_user_store

logger = logging.getLogger(__name__)

# ユーザー ID(置き場所のフォルダ名に使うため、使える文字を絞る)
USER_ID = re.compile(r"^[a-z0-9_-]{3,32}$")
# ゲスト番号(secrets.token_hex(16))
GUEST_ID = re.compile(r"^[0-9a-f]{32}$")
JWT_ALGORITHM = "HS256"

# パスワードのハッシュ(scrypt)の設定
_SCRYPT_N = 2**14
_SCRYPT_R = 8
_SCRYPT_P = 1
_SCRYPT_LEN = 32
_SALT_BYTES = 16
# ローカルで AUTH_SECRET_KEY が空のときに使う、起動ごとの鍵
_EPHEMERAL_KEY = secrets.token_urlsafe(32)


class AuthError(RuntimeError):
    """ログインの処理に失敗した(保存先を読めないなど)。ルータが 502 に変換する。"""


class AuthConfigError(AuthError):
    """署名の鍵が設定されていない。ルータが 503 に変換する。"""


class InvalidCredentialsError(AuthError):
    """ユーザー ID またはパスワードが違う。ルータが 401 に変換する。"""


class InvalidTokenError(AuthError):
    """トークンが無い・期限切れ・改ざんされている。ルータが 401 に変換する。"""


class Owner(BaseModel):
    """手持ちの服の持ち主。ログインしたユーザーか、ゲスト。"""

    kind: Literal["user", "guest"]
    id: str


class IssuedToken(BaseModel):
    """発行したトークンと、その持ち主・期限。"""

    token: str
    owner: Owner
    expires_at: datetime


# --- パスワード -------------------------------------------------------------


def hash_password(password: str) -> str:
    """パスワードをソルト付きの scrypt でハッシュにする(元には戻せない)。"""
    salt = os.urandom(_SALT_BYTES)
    digest = _scrypt(password, salt, _SCRYPT_N, _SCRYPT_R, _SCRYPT_P)
    return "$".join(
        [
            "scrypt",
            str(_SCRYPT_N),
            str(_SCRYPT_R),
            str(_SCRYPT_P),
            base64.b64encode(salt).decode(),
            base64.b64encode(digest).decode(),
        ]
    )


def verify_password(password: str, stored: str) -> bool:
    """パスワードがハッシュと一致するか。形式が不正なら False。"""
    try:
        scheme, n, r, p, salt, digest = stored.split("$")
        if scheme != "scrypt":
            return False
        expected = base64.b64decode(digest)
        actual = _scrypt(password, base64.b64decode(salt), int(n), int(r), int(p))
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(actual, expected)


def _scrypt(password: str, salt: bytes, n: int, r: int, p: int) -> bytes:
    return hashlib.scrypt(password.encode("utf-8"), salt=salt, n=n, r=r, p=p, dklen=_SCRYPT_LEN)


# 存在しない ID のときに照合するダミー(ID の有無で処理時間が変わらないようにする)
_DUMMY_HASH = hash_password(secrets.token_urlsafe(16))


# --- トークン ---------------------------------------------------------------


def issue_token(owner: Owner, secret: str, now: datetime, days: int) -> IssuedToken:
    """持ち主のトークンを発行する。"""
    expires_at = now + timedelta(days=days)
    payload = {
        "sub": owner.id,
        "kind": owner.kind,
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
    }
    token = jwt.encode(payload, secret, algorithm=JWT_ALGORITHM)
    return IssuedToken(token=token, owner=owner, expires_at=expires_at)


def decode_token(token: str, secret: str, now: datetime) -> Owner:
    """トークンを確かめて持ち主を返す。署名・期限・中身のどれかが不正なら InvalidTokenError。"""
    try:
        payload = jwt.decode(
            token,
            secret,
            algorithms=[JWT_ALGORITHM],
            options={
                "require": ["sub", "exp", "iat"],
                "verify_exp": False,
                "verify_iat": False,
            },
        )
        exp, iat = int(payload["exp"]), int(payload["iat"])
    except (jwt.PyJWTError, TypeError, ValueError) as exc:
        raise InvalidTokenError("トークンが不正です。") from exc
    # 期限・発行日時は now で確かめる(テストで時刻を渡せるようにするため)。
    # 発行日時は時計のずれを 1 分まで許す
    current = int(now.timestamp())
    if exp <= current:
        raise InvalidTokenError("トークンの期限が切れています。")
    if iat > current + 60:
        raise InvalidTokenError("トークンが不正です。")

    kind, sub = payload.get("kind"), payload.get("sub")
    if kind == "user" and isinstance(sub, str) and USER_ID.match(sub):
        return Owner(kind="user", id=sub)
    if kind == "guest" and isinstance(sub, str) and GUEST_ID.match(sub):
        return Owner(kind="guest", id=sub)
    raise InvalidTokenError("トークンが不正です。")


# --- サービス ---------------------------------------------------------------


class AuthService:
    """ログイン・ゲストの発行・トークンの確認のユースケース。"""

    def __init__(self, settings: Settings | None = None, users: UserStore | None = None) -> None:
        # users はテストで差し替えるためのもの
        self._settings = settings or get_settings()
        self._users = users or create_user_store(self._settings)

    def login(self, user_id: str, password: str, now: datetime | None = None) -> IssuedToken:
        """ID とパスワードを確かめ、ユーザーのトークンを発行する。"""
        secret = self._secret()
        try:
            record = self._users.get(user_id) if USER_ID.match(user_id) else None
        except UserStoreError as exc:
            raise AuthError(f"ユーザーの一覧を読み込めませんでした: {exc}") from exc
        # 存在しない ID でもダミーで照合し、処理時間をそろえる
        matched = verify_password(password, record.password if record else _DUMMY_HASH)
        if record is None or not matched:
            logger.info("ログインに失敗しました: user_id=%s", user_id)
            raise InvalidCredentialsError("ユーザー ID またはパスワードが違います。")
        logger.info("ログインしました: user_id=%s", user_id)
        return issue_token(
            Owner(kind="user", id=user_id), secret, now or _now(), self._settings.auth_token_days
        )

    def guest(self, now: datetime | None = None) -> IssuedToken:
        """新しいゲスト番号のトークンを発行する。"""
        owner = Owner(kind="guest", id=secrets.token_hex(16))
        return issue_token(owner, self._secret(), now or _now(), self._settings.auth_token_days)

    def owner_from_token(self, token: str, now: datetime | None = None) -> Owner:
        """トークンの持ち主を返す。ユーザーなら、今も登録されているかを確かめる。"""
        owner = decode_token(token, self._secret(), now or _now())
        if owner.kind == "user":
            try:
                exists = self._users.get(owner.id) is not None
            except UserStoreError as exc:
                raise AuthError(f"ユーザーの一覧を読み込めませんでした: {exc}") from exc
            if not exists:
                raise InvalidTokenError("ユーザーが登録されていません。")
        return owner

    def _secret(self) -> str:
        if self._settings.auth_secret_key:
            return self._settings.auth_secret_key
        if self._settings.is_local:
            return _EPHEMERAL_KEY
        raise AuthConfigError("AUTH_SECRET_KEY が未設定のため、ログインを使えません。")


def _now() -> datetime:
    return datetime.now(UTC)


def get_auth_service() -> AuthService:
    """FastAPI の Depends 用ファクトリ。テスト時は override して差し替える。"""
    return AuthService()
