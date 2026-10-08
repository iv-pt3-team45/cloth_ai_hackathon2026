"""API ルータの集約。新しい機能のルータはここに追加する。"""

from fastapi import APIRouter

from app.api.routes import culture, health, live, outfit, venue, wardrobe, youtube

api_router = APIRouter()
api_router.include_router(health.router)
# チャット(エージェント)の API は閉じている(spec 036)。画面で使っておらず、
# 画像・動画の生成ツールで費用がかさむおそれがあるため。
# 開くときは routes/chat.py の router をここに戻す。エージェントは CLI から使える
api_router.include_router(youtube.router)
api_router.include_router(culture.router)
api_router.include_router(live.router)
api_router.include_router(wardrobe.router)
api_router.include_router(outfit.router)
api_router.include_router(venue.router)
