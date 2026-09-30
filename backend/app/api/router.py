"""API ルータの集約。新しい機能のルータはここに追加する。"""

from fastapi import APIRouter

from app.api.routes import chat, culture, health, live, youtube

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(chat.router)
api_router.include_router(youtube.router)
api_router.include_router(culture.router)
api_router.include_router(live.router)
