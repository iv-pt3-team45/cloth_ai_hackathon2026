"""ログインとゲストの通行証(トークン)のエンドポイント(spec 038)。

ログアウトの API は無い(画面がトークンを捨てるだけ。サーバーは状態を覚えていない)。
"""

from fastapi import APIRouter

from app.api.deps import AuthServiceDep, CurrentOwner, auth_error_to_http, unauthorized
from app.schemas.auth import LoginRequest, MeResponse, TokenResponse
from app.services.auth import AuthError, InvalidCredentialsError, IssuedToken

router = APIRouter(prefix="/auth", tags=["auth"])


def _to_response(issued: IssuedToken) -> TokenResponse:
    owner = issued.owner
    return TokenResponse(
        token=issued.token,
        kind=owner.kind,
        user_id=owner.id if owner.kind == "user" else None,
        expires_at=issued.expires_at,
    )


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, auth: AuthServiceDep) -> TokenResponse:
    try:
        return _to_response(auth.login(payload.user_id, payload.password))
    except InvalidCredentialsError as exc:
        raise unauthorized(str(exc)) from exc
    except AuthError as exc:
        raise auth_error_to_http(exc) from exc


@router.post("/guest", response_model=TokenResponse)
def guest(auth: AuthServiceDep) -> TokenResponse:
    try:
        return _to_response(auth.guest())
    except AuthError as exc:
        raise auth_error_to_http(exc) from exc


@router.get("/me", response_model=MeResponse)
def me(owner: CurrentOwner) -> MeResponse:
    return MeResponse(kind=owner.kind, user_id=owner.id if owner.kind == "user" else None)
