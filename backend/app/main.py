"""FastAPI アプリケーションのエントリポイント。"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.router import api_router
from app.core.config import get_settings
from app.core.logging import setup_logging
from app.services.input_guard import UnsafeInputError


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    setup_logging(settings.log_level, json_format=not settings.is_local)
    yield


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        docs_url="/docs",
        openapi_url="/openapi.json",
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(api_router, prefix="/api/v1")

    @app.exception_handler(UnsafeInputError)
    async def unsafe_input(request: Request, exc: UnsafeInputError) -> JSONResponse:
        # 利用者の入力に不審な言い回しがあった(spec 036)。理由を 400 で返す
        return JSONResponse(status_code=400, content={"detail": str(exc)})

    return app


app = create_app()
