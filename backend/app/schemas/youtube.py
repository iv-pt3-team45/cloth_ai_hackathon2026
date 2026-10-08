"""MV のメタ情報取得 API のリクエスト / レスポンススキーマ(spec 007)。"""

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, Field, StringConstraints

from app.schemas.common import GuardedRequest


class LookupRequest(GuardedRequest):
    query: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)
    ] = Field(..., description="YouTube の動画 URL または MV 名")


class VideoInfo(BaseModel):
    """1 本の動画のメタ情報。後続の公演情報の調査にもこの単位で渡す。"""

    video_id: str = Field(..., description="YouTube の動画 ID")
    url: str = Field(..., description="動画のリンク(https://www.youtube.com/watch?v=...)")
    artist: str = Field(..., description="アーティスト名(分解できなければチャンネル名)")
    song_title: str = Field(..., description="曲名(分解できなければ動画タイトル)")
    title_parsed: bool = Field(..., description="タイトルからアーティスト名・曲名を分解できたか")
    title: str = Field(..., description="動画タイトル(YouTube の値そのまま)")
    channel_title: str = Field(..., description="チャンネル名(YouTube の値そのまま)")
    published_at: datetime | None = Field(default=None, description="公開日時")
    thumbnail_url: str = Field(default="", description="サムネイル画像の URL")
    description: str = Field(default="", description="概要欄")


class VideoCandidate(BaseModel):
    """MV 名で検索したときの候補 1 件。"""

    video_id: str
    url: str
    title: str
    channel_title: str
    published_at: datetime | None = None
    thumbnail_url: str = ""


class LookupResponse(BaseModel):
    input_type: Literal["url", "keyword"] = Field(
        ..., description="入力の種類(url=動画 URL / keyword=MV 名)"
    )
    video: VideoInfo | None = Field(default=None, description="URL を入力したときの動画情報")
    candidates: list[VideoCandidate] = Field(
        default_factory=list, description="MV 名を入力したときの候補(0 件なら空)"
    )
