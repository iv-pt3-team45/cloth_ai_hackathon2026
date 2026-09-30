"""アーティストのカルチャー情報 API のリクエスト / レスポンススキーマ(spec 008)。"""

from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.youtube import VideoInfo


class CultureRequest(BaseModel):
    video: VideoInfo = Field(..., description="spec 007 で取得した動画情報")


class FashionInfo(BaseModel):
    """ファッション・ビジュアル(Web 検索が根拠)。"""

    styles: list[str] = Field(default_factory=list, description="衣装・私服の系統")
    colors: list[str] = Field(default_factory=list, description="衣装・アートワークに多い色")
    items: list[str] = Field(default_factory=list, description="象徴的なアイテム")
    worldview: str = Field(default="", description="MV・アートワークの世界観")
    source_indices: list[int] = Field(default_factory=list, description="根拠の出典番号")


class BackgroundInfo(BaseModel):
    """経歴・音楽性(Web 検索が根拠)。"""

    summary: str = Field(default="", description="どんなアーティストか")
    history: list[str] = Field(default_factory=list, description="活動の歩み(年と出来事)")
    genres: list[str] = Field(default_factory=list, description="ジャンル")
    representative_songs: list[str] = Field(default_factory=list, description="代表曲")
    musical_traits: str = Field(default="", description="音楽的な特徴")
    source_indices: list[int] = Field(default_factory=list, description="根拠の出典番号")


class OutfitItem(BaseModel):
    """MV で着ている服 1 点。項目は服インデックス(spec 005 の ClothItem)と揃えている。"""

    category: str = Field(default="", description="種類")
    material: str = Field(default="", description="素材(不明なら「不明」)")
    shape: str = Field(default="", description="形・シルエット")
    colors: list[str] = Field(default_factory=list, description="色。目立つ順")
    pattern: str = Field(default="", description="柄")
    style: str = Field(default="", description="系統")
    notes: str = Field(default="", description="特徴")


class OutfitLook(BaseModel):
    """MV の衣装 1 着分(シーンごと)。"""

    label: str = Field(default="", description="衣装の呼び名(例: メインの衣装)")
    items: list[OutfitItem] = Field(default_factory=list)


class MvOutfit(BaseModel):
    """この MV の衣装(MV の映像が根拠)。"""

    status: Literal["ok", "unavailable", "skipped"] = Field(
        ..., description="ok=解析できた / unavailable=解析できなかった / skipped=使わなかった"
    )
    message: str = Field(default="", description="unavailable / skipped の理由")
    looks: list[OutfitLook] = Field(default_factory=list)


class Source(BaseModel):
    """Web 検索の出典。`index` は各セクションの `source_indices` から参照される。"""

    index: int = Field(..., description="出典番号(1 始まり)")
    title: str
    url: str
    domain: str = ""


class CultureResponse(BaseModel):
    artist: str = Field(..., description="Gemini が特定したアーティスト名")
    identified: bool = Field(..., description="アーティストを特定できたか")
    message: str = Field(default="", description="特定できなかった場合の理由")
    fashion: FashionInfo = Field(default_factory=FashionInfo)
    background: BackgroundInfo = Field(default_factory=BackgroundInfo)
    mv_outfit: MvOutfit
    sources: list[Source] = Field(default_factory=list)
    search_suggestions_html: str = Field(
        default="", description="Google 検索の検索候補(加工せずに表示する HTML)"
    )
    web_search_queries: list[str] = Field(default_factory=list, description="実行された検索クエリ")
    model: str = Field(..., description="使用したモデル名")
