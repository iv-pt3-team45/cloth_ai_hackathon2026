"""ログインとゲストの API の入出力(spec 038)。"""

import datetime as dt
from typing import Literal

from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    user_id: str = Field(..., min_length=1, max_length=64, description="ユーザー ID")
    password: str = Field(..., min_length=1, max_length=256, description="パスワード")


class MeResponse(BaseModel):
    kind: Literal["user", "guest"] = Field(..., description="user = ログイン中 / guest = ゲスト")
    user_id: str | None = Field(default=None, description="ログイン中のユーザー ID(ゲストは null)")
    expires_at: dt.datetime | None = Field(default=None, description="トークンの期限")


class TokenResponse(MeResponse):
    token: str = Field(..., description="以降の API に `Authorization: Bearer <token>` で付ける")
