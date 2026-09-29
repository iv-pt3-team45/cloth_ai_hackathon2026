"""アーティストのカルチャー情報を Gemini で調べるエンドポイント(spec 008)。"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.culture import CultureRequest, CultureResponse
from app.services.culture import (
    CultureError,
    CultureQuotaError,
    CultureService,
    CultureTimeoutError,
    get_culture_service,
)

router = APIRouter(prefix="/culture", tags=["culture"])


@router.post("/research", response_model=CultureResponse)
async def research(
    payload: CultureRequest,
    service: Annotated[CultureService, Depends(get_culture_service)],
) -> CultureResponse:
    try:
        return await service.research(payload.video)
    except CultureError as exc:
        if isinstance(exc, CultureQuotaError):
            code = status.HTTP_503_SERVICE_UNAVAILABLE
        elif isinstance(exc, CultureTimeoutError):
            code = status.HTTP_504_GATEWAY_TIMEOUT
        else:
            code = status.HTTP_502_BAD_GATEWAY
        raise HTTPException(status_code=code, detail=str(exc)) from exc
