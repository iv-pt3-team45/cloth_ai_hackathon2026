"""API ルータの集約。新しい機能のルータはここに追加する。"""

from fastapi import APIRouter

from app.api.routes import chat, culture, health, live, outfit, wardrobe, youtube

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(chat.router)
api_router.include_router(youtube.router)
api_router.include_router(culture.router)
api_router.include_router(live.router)
api_router.include_router(wardrobe.router)
api_router.include_router(outfit.router)
