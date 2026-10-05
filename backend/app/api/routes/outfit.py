"""手持ちの服からのコーデ提案と、マネキンに着せた画像の生成のエンドポイント(spec 011)。"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.outfit import (
    OutfitImageRequest,
    OutfitImageResponse,
    OutfitSuggestion,
    OutfitSuggestRequest,
)
from app.services.outfit import (
    OutfitError,
    OutfitInputError,
    OutfitQuotaError,
    OutfitService,
    OutfitTimeoutError,
    get_outfit_service,
)

router = APIRouter(prefix="/outfit", tags=["outfit"])

Service = Annotated[OutfitService, Depends(get_outfit_service)]

# 業務例外 → HTTP ステータス。上から順に照合する(該当しなければ 502)
_ERROR_STATUS: list[tuple[type[OutfitError], int]] = [
    (OutfitInputError, status.HTTP_400_BAD_REQUEST),
    (OutfitQuotaError, status.HTTP_503_SERVICE_UNAVAILABLE),
    (OutfitTimeoutError, status.HTTP_504_GATEWAY_TIMEOUT),
]


def _to_http(exc: OutfitError) -> HTTPException:
    code = next(
        (code for error_type, code in _ERROR_STATUS if isinstance(exc, error_type)),
        status.HTTP_502_BAD_GATEWAY,
    )
    return HTTPException(status_code=code, detail=str(exc))


@router.post("/suggest", response_model=OutfitSuggestion)
async def suggest(payload: OutfitSuggestRequest, service: Service) -> OutfitSuggestion:
    try:
        return await service.suggest(
            payload.video, payload.culture, payload.live, payload.venue_format
        )
    except OutfitError as exc:
        raise _to_http(exc) from exc


@router.post("/image", response_model=OutfitImageResponse)
async def image(payload: OutfitImageRequest, service: Service) -> OutfitImageResponse:
    try:
        # title は互換のため受け取るが、画像の生成には使わない(spec 011 design.md 6.2)
        return await service.generate_image(payload.item_ids)
    except OutfitError as exc:
        raise _to_http(exc) from exc
