"""手持ちの服の写真を登録・一覧・削除するエンドポイント(spec 010)。

解析以外は、ログイン・ゲストのトークンが必須(spec 038)。服はトークンの持ち主ごとに分かれる。

解析(spec 005 の同期の呼び出し)とファイルの読み書きを行うため、ハンドラは同期関数にして
FastAPI のスレッドプールで動かす。
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status

from app.api.deps import CurrentOwner
from app.schemas.wardrobe import (
    AnalyzeRequest,
    AnalyzeResponse,
    RegisterRequest,
    RegisterResponse,
    WardrobeListResponse,
)
from app.services.wardrobe_registry import (
    WardrobeError,
    WardrobeImageTooLargeError,
    WardrobeInputError,
    WardrobeNotFoundError,
    WardrobeQuotaError,
    WardrobeService,
    get_wardrobe_service,
)

router = APIRouter(prefix="/wardrobe", tags=["wardrobe"])

Service = Annotated[WardrobeService, Depends(get_wardrobe_service)]

# 業務例外 → HTTP ステータス。上から順に照合する(該当しなければ 502)
_ERROR_STATUS: list[tuple[type[WardrobeError], int]] = [
    (WardrobeImageTooLargeError, status.HTTP_413_CONTENT_TOO_LARGE),
    (WardrobeInputError, status.HTTP_400_BAD_REQUEST),
    (WardrobeNotFoundError, status.HTTP_404_NOT_FOUND),
    (WardrobeQuotaError, status.HTTP_503_SERVICE_UNAVAILABLE),
]


def _to_http(exc: WardrobeError) -> HTTPException:
    code = next(
        (code for error_type, code in _ERROR_STATUS if isinstance(exc, error_type)),
        status.HTTP_502_BAD_GATEWAY,
    )
    return HTTPException(status_code=code, detail=str(exc))


@router.post("/analyze", response_model=AnalyzeResponse)
def analyze(payload: AnalyzeRequest, service: Service) -> AnalyzeResponse:
    try:
        return service.analyze(payload.image)
    except WardrobeError as exc:
        raise _to_http(exc) from exc


@router.get("/items", response_model=WardrobeListResponse)
def list_items(service: Service, owner: CurrentOwner) -> WardrobeListResponse:
    try:
        items = service.for_owner(owner).list_items()
    except WardrobeError as exc:
        raise _to_http(exc) from exc
    return WardrobeListResponse(items=items, count=len(items))


@router.post("/items", response_model=RegisterResponse, status_code=status.HTTP_201_CREATED)
def register(payload: RegisterRequest, service: Service, owner: CurrentOwner) -> RegisterResponse:
    try:
        return RegisterResponse(items=service.for_owner(owner).register(payload))
    except WardrobeError as exc:
        raise _to_http(exc) from exc


@router.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(item_id: str, service: Service, owner: CurrentOwner) -> Response:
    try:
        service.for_owner(owner).delete(item_id)
    except WardrobeError as exc:
        raise _to_http(exc) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/images/{image}")
def read_image(image: str, service: Service, owner: CurrentOwner) -> Response:
    try:
        data, mime_type = service.for_owner(owner).read_image(image)
    except WardrobeError as exc:
        raise _to_http(exc) from exc
    return Response(content=data, media_type=mime_type)
