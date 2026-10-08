"""手持ちの服の登録 API のリクエスト / レスポンススキーマ(spec 010)。

季節・暖かさ・使う場面の選択肢はここを正とし、services(解析結果の整え方)もここから取り出す。
"""

import datetime as dt
from typing import Annotated, Literal

from pydantic import BaseModel, Field, StringConstraints, model_validator

from app.schemas.common import GuardedRequest

Season = Literal["春", "夏", "秋", "冬"]
Warmth = Literal["薄手", "普通", "厚手"]
# 「きれいめ」は画面と指示では「きれいめ(食事・オフィス)」と説明する
Occasion = Literal["普段着", "きれいめ", "フォーマル", "スポーツ・アウトドア", "ライブ・フェス"]
ImageMimeType = Literal["image/jpeg", "image/png", "image/webp"]

_Text = Annotated[str, StringConstraints(strip_whitespace=True, max_length=200)]
_LongText = Annotated[str, StringConstraints(strip_whitespace=True, max_length=1000)]


class WardrobeImage(BaseModel):
    """服の写真 1 枚。チャットの添付と同じく base64 で受け取る。"""

    mime_type: ImageMimeType = Field(..., description="画像の形式(jpeg / png / webp)")
    data: str = Field(..., min_length=1, description="base64 エンコードした画像")


class ClothAttributes(BaseModel):
    """服 1 点の属性。項目は spec 005 の ClothItem に季節・暖かさ・使う場面を足したもの。"""

    category: _Text = Field(default="", description="種類(Tシャツ、パンツなど)")
    material: _Text = Field(default="", description="素材(不明なら「不明」)")
    shape: _Text = Field(default="", description="形・シルエット")
    colors: list[_Text] = Field(default_factory=list, max_length=10, description="色。目立つ順")
    pattern: _Text = Field(default="", description="柄")
    style: _Text = Field(default="", description="系統(自由な語)")
    notes: _LongText = Field(default="", description="プリントの文言や装飾などの特徴")
    seasons: list[Season] = Field(default_factory=list, description="着るのに向いている季節")
    warmth: Warmth | None = Field(default=None, description="暖かさ。分からなければ null")
    occasions: list[Occasion] = Field(default_factory=list, description="使う場面")


class AnalyzeRequest(BaseModel):
    image: WardrobeImage


class AnalyzeResponse(BaseModel):
    items: list[ClothAttributes] = Field(
        default_factory=list, description="写っている服。服が写っていなければ空"
    )
    summary: str = Field(default="", description="写真全体の説明")
    model: str = Field(..., description="使用したモデル名")


class RegisterRequest(GuardedRequest):
    image: WardrobeImage
    items: list[ClothAttributes] = Field(
        ..., min_length=1, max_length=20, description="保存する服(利用者が確認・修正したもの)"
    )
    summary: _LongText = Field(default="", description="写真全体の説明")

    @model_validator(mode="after")
    def check_categories(self) -> "RegisterRequest":
        if any(not item.category for item in self.items):
            raise ValueError("種類が空の服があります。種類を入力してください")
        return self


class RegisteredCloth(ClothAttributes):
    """登録済みの服 1 点。"""

    id: str = Field(..., description="服の ID(削除に使う)")
    image: str = Field(..., description="写真のファイル名(GET /wardrobe/images/{image} で取得)")
    registered_at: dt.datetime | None = Field(default=None, description="登録日時")


class RegisterResponse(BaseModel):
    items: list[RegisteredCloth]


class WardrobeListResponse(BaseModel):
    items: list[RegisteredCloth] = Field(default_factory=list, description="新しい順")
    count: int
