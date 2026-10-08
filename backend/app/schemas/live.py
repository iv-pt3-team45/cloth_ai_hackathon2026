"""ライブ情報の検索 API のリクエスト / レスポンススキーマ(spec 009)。"""

import datetime as dt
from typing import Annotated, Literal

from pydantic import BaseModel, Field, StringConstraints, model_validator

from app.schemas.common import GuardedRequest
from app.schemas.culture import Source

WeatherKind = Literal["actual", "forecast", "not_yet", "unknown"]


class LiveSearchRequest(GuardedRequest):
    query: Annotated[str, StringConstraints(strip_whitespace=True, max_length=200)] = Field(
        default="", description="ライブ名・ツアー名・会場などのキーワード"
    )
    date: dt.date | None = Field(default=None, description="公演日(日本時間)")
    artist: Annotated[str, StringConstraints(strip_whitespace=True, max_length=200)] | None = Field(
        default=None,
        description="表示中の動画で分かっているアーティスト名。指定すると候補のアーティスト名は取得しない",
    )

    @model_validator(mode="after")
    def check_query_or_date(self) -> "LiveSearchRequest":
        if not self.query and self.date is None:
            raise ValueError("ライブ情報か日付のどちらかを入力してください")
        return self


class LiveWeather(BaseModel):
    """公演当日の天気。"""

    kind: WeatherKind = Field(
        ..., description="actual=実績 / forecast=予報 / not_yet=予報はまだ無い / unknown=不明"
    )
    summary: str = Field(default="", description="天気の概況(例: 晴れ時々曇り)")
    high_c: float | None = Field(default=None, description="最高気温(℃)")
    low_c: float | None = Field(default=None, description="最低気温(℃)")
    precipitation_chance: int | None = Field(default=None, description="降水確率(%)")


class LiveCandidate(BaseModel):
    """ライブの候補 1 件(1 公演日)。"""

    index: int = Field(..., description="候補の番号(1 始まり)")
    artist: str | None = Field(
        default=None, description="アーティスト名。リクエストで artist を指定した場合は null"
    )
    live_name: str = Field(default="", description="ライブ名・ツアー名")
    venue: str = Field(default="", description="会場名")
    location: str = Field(default="", description="所在地(都道府県・市区町村)")
    date: dt.date | None = Field(default=None, description="公演日")
    weather: LiveWeather
    source_indices: list[int] = Field(default_factory=list, description="根拠の出典番号")


class LiveSearchResponse(BaseModel):
    artist: str = Field(default="", description="リクエストで受け取ったアーティスト名")
    found: bool = Field(..., description="該当するライブが見つかったか")
    message: str = Field(default="", description="見つからなかった場合の理由")
    candidates: list[LiveCandidate] = Field(default_factory=list, description="最大 3 件")
    sources: list[Source] = Field(default_factory=list)
    search_suggestions_html: str = Field(
        default="", description="Google 検索の検索候補(加工せずに表示する HTML)"
    )
    web_search_queries: list[str] = Field(default_factory=list, description="実行された検索クエリ")
    model: str = Field(..., description="使用したモデル名")
