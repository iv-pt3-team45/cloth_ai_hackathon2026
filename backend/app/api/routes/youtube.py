"""YouTube の MV からメタ情報を取得するエンドポイント(spec 007)。"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.youtube import LookupRequest, LookupResponse
from app.services.youtube import (
    InvalidVideoUrlError,
    VideoNotFoundError,
    YouTubeError,
    YouTubeQuotaError,
    YouTubeService,
    get_youtube_service,
)

router = APIRouter(prefix="/youtube", tags=["youtube"])

# 業務例外 → HTTP ステータス。上から順に照合する(該当しなければ 502)
_ERROR_STATUS: list[tuple[type[YouTubeError], int]] = [
    (InvalidVideoUrlError, status.HTTP_400_BAD_REQUEST),
    (VideoNotFoundError, status.HTTP_404_NOT_FOUND),
    (YouTubeQuotaError, status.HTTP_503_SERVICE_UNAVAILABLE),
]


@router.post("/lookup", response_model=LookupResponse)
async def lookup(
    payload: LookupRequest,
    service: Annotated[YouTubeService, Depends(get_youtube_service)],
) -> LookupResponse:
    try:
        return await service.lookup(payload.query)
    except YouTubeError as exc:
        code = next(
            (code for error_type, code in _ERROR_STATUS if isinstance(exc, error_type)),
            status.HTTP_502_BAD_GATEWAY,
        )
        raise HTTPException(status_code=code, detail=str(exc)) from exc
