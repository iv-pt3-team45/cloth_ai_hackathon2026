"""手持ちの服からのコーデ提案 API のリクエスト / レスポンススキーマ(spec 011)。"""

from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints

from app.schemas.culture import CultureResponse
from app.schemas.live import LiveCandidate
from app.schemas.wardrobe import RegisteredCloth
from app.schemas.youtube import VideoInfo


class OutfitSuggestRequest(BaseModel):
    """提案の材料。画面が持っている内容をそのまま送る(手持ちの服はサーバが保存先から読む)。"""

    video: VideoInfo = Field(..., description="spec 007 の動画情報")
    culture: CultureResponse | None = Field(
        default=None, description="spec 008 のカルチャー情報(取得できていなければ null)"
    )
    live: LiveCandidate = Field(..., description="spec 009 で選んだライブ")


class SuggestedCloth(RegisteredCloth):
    """提案に使う手持ちの服 1 点。"""

    role: str = Field(default="", description="コーデの中の役割(トップス・ボトムスなど)")
    reason: str = Field(default="", description="この服を選んだ理由")


class OutfitSuggestion(BaseModel):
    title: str = Field(default="", description="コーデの名前")
    summary: str = Field(default="", description="コーデ全体の説明")
    points: list[str] = Field(
        default_factory=list, description="天気・場面・アーティストらしさなどのポイント"
    )
    items: list[SuggestedCloth] = Field(..., description="使う服(手持ちの服だけ)")
    excluded_count: int = Field(default=0, description="手持ちに無かったため提案から除いた服の数")
    model: str = Field(..., description="使用したモデル名")


class OutfitImageRequest(BaseModel):
    item_ids: list[str] = Field(
        ..., min_length=1, max_length=10, description="着せる手持ちの服の ID(提案の items の id)"
    )
    title: Annotated[str, StringConstraints(strip_whitespace=True, max_length=200)] = Field(
        default="", description="コーデの名前"
    )


class OutfitImageResponse(BaseModel):
    mime_type: str = Field(..., description="生成した画像の形式")
    data: str = Field(..., description="生成した画像(base64)")
    file_name: str = Field(..., description="保存したファイル名(created_images/)")
    model: str = Field(..., description="使用したモデル名")
