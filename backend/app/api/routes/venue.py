"""選んだライブの会場の形態(スタンディング / 着席 / 混在)を調べるエンドポイント(spec 014)。

画面はライブを選んだ時点でこれを呼び、確認タブに表示して、コーデ提案(spec 011)にも渡す。
F14 は失敗しても例外を投げない設計のため、失敗・時間切れも 200(format=unknown, status=error)で返す。
"""

from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.config import Settings, get_settings
from app.schemas.venue import VenueLookupRequest, VenueLookupResponse
from app.services.venue import VenueLookup, get_venue_lookup, lookup_venue_info

router = APIRouter(prefix="/venue", tags=["venue"])


@router.post("/lookup", response_model=VenueLookupResponse)
async def lookup(
    payload: VenueLookupRequest,
    settings: Annotated[Settings, Depends(get_settings)],
    venue_lookup: Annotated[VenueLookup, Depends(get_venue_lookup)],
) -> VenueLookupResponse:
    info = await lookup_venue_info(
        payload.venue,
        location=payload.location,
        live_name=payload.live_name,
        live_date=payload.date.isoformat() if payload.date else "",
        settings=settings,
        lookup=venue_lookup,
    )
    return VenueLookupResponse(
        venue_name=info.venue_name,
        format=info.format,
        status=info.status,
        message=info.message,
    )
