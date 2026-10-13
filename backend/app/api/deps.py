"""ルータで共通に使う依存関係(spec 038)。"""

from typing import Annotated

from fastapi import Depends, Header, HTTPException, status

from app.services.auth import (
    AuthConfigError,
    AuthError,
    AuthService,
    InvalidTokenError,
    Owner,
    get_auth_service,
)

AuthServiceDep = Annotated[AuthService, Depends(get_auth_service)]


def auth_error_to_http(exc: AuthError) -> HTTPException:
    """ログインの業務例外を HTTP のエラーにする。"""
    if isinstance(exc, AuthConfigError):
        return HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))
    return HTTPException(status.HTTP_502_BAD_GATEWAY, detail=str(exc))


def unauthorized(message: str) -> HTTPException:
    return HTTPException(
        status.HTTP_401_UNAUTHORIZED,
        detail=message,
        headers={"WWW-Authenticate": "Bearer"},
    )


def bearer_token(authorization: str | None) -> str | None:
    """`Authorization: Bearer <トークン>` からトークンを取り出す。無ければ None。"""
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        return None
    return token.strip()


def current_owner(
    auth: AuthServiceDep,
    authorization: Annotated[str | None, Header()] = None,
) -> Owner:
    """手持ちの服・コーデ提案の持ち主。トークンが無い・無効なら 401。"""
    token = bearer_token(authorization)
    if token is None:
        raise unauthorized("ログインまたはゲストの準備ができていません。")
    try:
        return auth.owner_from_token(token)
    except InvalidTokenError as exc:
        raise unauthorized("ログインの期限が切れました。もう一度ログインしてください。") from exc
    except AuthError as exc:
        raise auth_error_to_http(exc) from exc


CurrentOwner = Annotated[Owner, Depends(current_owner)]
