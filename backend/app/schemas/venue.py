"""会場の形態を調べる API のリクエスト / レスポンススキーマ(spec 014)。"""

import datetime as dt
from enum import StrEnum
from typing import Annotated, Literal

from pydantic import BaseModel, Field, StringConstraints


class VenueFormat(StrEnum):
    """会場の座席形態。"""

    STANDING = "standing"
    SEATED = "seated"
    # スタンディングと着席の両方がある(例: 1 階スタンディング・2 階指定席)。
    # どちらになるかはチケットの種別による
    MIXED = "mixed"
    UNKNOWN = "unknown"


_Text = Annotated[str, StringConstraints(strip_whitespace=True, max_length=200)]


class VenueLookupRequest(BaseModel):
    """選んだライブ(spec 009 の LiveCandidate)の値をそのまま送る。会場名以外は任意の手がかり。"""

    venue: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)
    ] = Field(..., description="会場名")
    location: _Text = Field(default="", description="所在地(都道府県・市区町村)")
    live_name: _Text = Field(default="", description="ライブ名・ツアー名")
    date: dt.date | None = Field(default=None, description="公演日")


class VenueLookupResponse(BaseModel):
    """形態だけを返す(グラウンディングの説明文は返さない。画面に出すのはラベルだけのため)。"""

    venue_name: str = Field(..., description="調べた会場名")
    format: VenueFormat = Field(..., description="standing / seated / mixed / unknown")
    status: Literal["ok", "error"] = Field(..., description="error のとき format は unknown")
    message: str = Field(default="", description="status=error のときの理由")
