"""ライブ情報を Gemini + Google 検索で調べるエンドポイント(spec 009)。"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.live import LiveSearchRequest, LiveSearchResponse
from app.services.live import (
    LiveSearchError,
    LiveSearchQuotaError,
    LiveSearchTimeoutError,
    LiveService,
    get_live_service,
)

router = APIRouter(prefix="/live", tags=["live"])


@router.post("/search", response_model=LiveSearchResponse)
async def search(
    payload: LiveSearchRequest,
    service: Annotated[LiveService, Depends(get_live_service)],
) -> LiveSearchResponse:
    try:
        return await service.search(payload.query, payload.date, payload.artist)
    except LiveSearchError as exc:
        if isinstance(exc, LiveSearchQuotaError):
            code = status.HTTP_503_SERVICE_UNAVAILABLE
        elif isinstance(exc, LiveSearchTimeoutError):
            code = status.HTTP_504_GATEWAY_TIMEOUT
        else:
            code = status.HTTP_502_BAD_GATEWAY
        raise HTTPException(status_code=code, detail=str(exc)) from exc
