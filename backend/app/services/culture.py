"""アーティストのカルチャー情報を Gemini で調べて整理する(spec 008)。

1 回の取得で Gemini を 3 回呼ぶ。

1. 調べる: Google 検索(グラウンディング)ありで、自由文で調べさせる。出典と検索候補もここで得る。
2. 整理する: 検索なしで、1. の本文を JSON に整理させる。
3. MV の衣装: YouTube の URL を渡し、映像から衣装を読み取らせる(1. → 2. と並行に実行する)。

検索と JSON 出力を 1 回にまとめないのは、同時に使うと出典(grounding_chunks)が
空になる事例があるため。
結果は保存しない(グラウンディング結果の保存は利用規約上の問題になるおそれがあるため)。
"""

import asyncio
import logging

from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from app.core.config import Settings, get_settings
from app.schemas.culture import (
    BackgroundInfo,
    CultureResponse,
    FashionInfo,
    MvOutfit,
    OutfitItem,
    OutfitLook,
)
from app.schemas.youtube import VideoInfo
from app.services.cloth_index import ClothItem
from app.services.grounding import (
    NO_AFC,
    WebResearch,
    clean_list,
    clean_text,
    grounded_research,
    is_quota_error,
    valid_indices,
)
from app.services.media import get_media_client

logger = logging.getLogger(__name__)

# プロンプトが膨らむのを防ぐため、概要欄は先頭だけを渡す
MAX_DESCRIPTION_CHARS = 1500

_STRUCTURE_INSTRUCTION = """\
あなたは調査メモを整理する編集者です。調査メモの内容を、指定された JSON の形に整理してください。

- メモに書かれていない情報を足さないこと。「情報なし」の項目は空(空文字・空の配列)にすること。
- styles / colors / items / genres は短く一般的な語にすること
  (例: 「ストリート」「黒」「ブーツ」「J-POP」)。
- history は「2019年 結成」のように、年と出来事を 1 件ずつ書くこと。
- メモ中の [1] [2] のような番号は出典番号。fashion と background のそれぞれで、
  根拠にした番号を source_indices に入れること。
- メモでアーティストを特定できていない場合は identified を false にし、message に理由を書くこと。
"""

_OUTFIT_INSTRUCTION = """\
あなたはスタイリストです。
この MV の映像を見て、出演者(アーティスト)が着ている衣装を記録してください。

- 衣装やシーンごとに looks に分け、label に「メインの衣装」「サビのシーン」など
  分かりやすい名前を付けること。
- 各アイテムは、種類(category)・素材(material)・形(shape)・色(colors)・柄(pattern)・
  系統(style)・特徴(notes)で書くこと。系統は「カジュアル」「ストリート」のような一般的な呼び方にすること。
- 素材が分からなければ「不明」と書くこと。色は目立つ順に並べること。
- 映像から分からないことは書かないこと。人物が映っていない場合は looks を空にすること。
"""


class CultureError(RuntimeError):
    """カルチャー情報の取得に失敗したときの例外。ルータが 502 に変換する。"""


class CultureQuotaError(CultureError):
    """Gemini のクォータ超過。時間をおけば回復するため、ルータが 503 に変換する。"""


class CultureTimeoutError(CultureError):
    """待ち時間の上限を超えた。ルータが 504 に変換する。"""


# --- モデルの構造化出力(API の契約とは分ける) ------------------------------


class _FashionOutput(BaseModel):
    styles: list[str] = Field(description="衣装・私服の系統(例: ストリート、モード、ガーリー)")
    colors: list[str] = Field(description="衣装・アートワークに多い色(例: 黒、白)")
    items: list[str] = Field(description="そのアーティストを象徴するアイテム(例: ベレー帽)")
    worldview: str = Field(description="MV・アートワークに共通するモチーフや雰囲気")
    source_indices: list[int] = Field(description="根拠にした出典番号([n] の n)")


class _BackgroundOutput(BaseModel):
    summary: str = Field(description="どんなアーティストか(1〜2 文)")
    history: list[str] = Field(description="活動の歩み。「2019年 結成」のように年と出来事")
    genres: list[str] = Field(description="音楽のジャンル")
    representative_songs: list[str] = Field(description="代表曲")
    musical_traits: str = Field(description="作風・影響を受けたものなど音楽的な特徴")
    source_indices: list[int] = Field(description="根拠にした出典番号([n] の n)")


class StructuredCulture(BaseModel):
    """2. 整理する の出力。"""

    identified: bool = Field(description="アーティストを特定できたか")
    artist: str = Field(description="特定したアーティスト名。特定できなければ空")
    message: str = Field(description="特定できなかった場合の理由。特定できたら空")
    fashion: _FashionOutput
    background: _BackgroundOutput


class _LookOutput(BaseModel):
    label: str = Field(description="衣装の呼び名(例: メインの衣装、サビのシーン)")
    items: list[ClothItem] = Field(description="その衣装を構成するアイテム")


class VideoOutfitAnalysis(BaseModel):
    """3. MV の衣装 の出力。"""

    looks: list[_LookOutput] = Field(description="衣装・シーンごとの記録")
    summary: str = Field(description="衣装全体の印象")


# --- プロンプトの組み立て --------------------------------------------------


def _video_summary(video: VideoInfo) -> str:
    """動画の要点をプロンプト用の箇条書きにする。"""
    if video.title_parsed:
        artist = f"アーティスト名(タイトルからの推定): {video.artist}"
    else:
        artist = (
            "アーティスト名: 不明(タイトルから分解できなかった。"
            f"次の値はチャンネル名であり、アーティスト名とは限らない: {video.artist})"
        )
    published = video.published_at.date().isoformat() if video.published_at else "不明"
    description = video.description[:MAX_DESCRIPTION_CHARS]
    return (
        f"- 動画タイトル: {video.title}\n"
        f"- チャンネル名: {video.channel_title}\n"
        f"- {artist}\n"
        f"- 曲名(推定): {video.song_title}\n"
        f"- 公開日: {published}\n"
        f"- 概要欄(先頭 {MAX_DESCRIPTION_CHARS} 文字まで):\n{description}"
    )


def build_research_prompt(video: VideoInfo) -> str:
    """1. 調べる のプロンプト。"""
    return f"""\
あなたは音楽とファッションに詳しいリサーチャーです。
次の YouTube 動画のアーティストについて、Google 検索で調べて日本語でまとめてください。

# 動画
{_video_summary(video)}

# 手順
1. まず、この動画のアーティストを特定してください。特定できない場合(音楽と関係のない動画など)は、
   「特定できませんでした」とその理由だけを書き、以降の項目は書かないでください。推測で埋めないでください。
2. ファッション・ビジュアル: スタイルの傾向、衣装やアートワークによく使う色、定番のアイテム、
   MV やアートワークの世界観
3. 経歴・音楽性: どんなアーティストか(1〜2 文)、活動の歩み(年と出来事)、ジャンル、
   代表曲、音楽的な特徴

Web で確認できた内容だけを書き、見つからない項目は「情報なし」と書いてください。
"""


def build_structure_prompt(video: VideoInfo, research_text: str) -> str:
    """2. 整理する のプロンプト。"""
    return f"# 動画\n{_video_summary(video)}\n\n# 調査メモ\n{research_text}"


def build_outfit_parts(video_url: str) -> list[types.Part]:
    """3. MV の衣装 の入力。動画はダウンロードせず YouTube の URL をそのまま渡す。"""
    return [
        types.Part(file_data=types.FileData(file_uri=video_url, mime_type="video/mp4")),
        types.Part.from_text(text="この MV の衣装を記録してください。"),
    ]


def to_culture_error(exc: Exception, action: str) -> CultureError:
    """Gemini の例外を業務例外に変換する。"""
    if isinstance(exc, CultureError):
        return exc
    if is_quota_error(exc):
        return CultureQuotaError(
            "Gemini のクォータ(利用上限)を超えました。時間をおいて再度お試しください。"
        )
    return CultureError(f"{action}に失敗しました: {exc}")


def build_response(
    research: WebResearch, structured: StructuredCulture, outfit: MvOutfit, model: str
) -> CultureResponse:
    """3 つの結果を API のレスポンスにまとめる。"""
    count = len(research.sources)
    fashion, background = structured.fashion, structured.background

    if structured.identified:
        message = ""
        fashion_info = FashionInfo(
            styles=clean_list(fashion.styles),
            colors=clean_list(fashion.colors),
            items=clean_list(fashion.items),
            worldview=clean_text(fashion.worldview),
            source_indices=valid_indices(fashion.source_indices, count),
        )
        background_info = BackgroundInfo(
            summary=clean_text(background.summary),
            history=clean_list(background.history),
            genres=clean_list(background.genres),
            representative_songs=clean_list(background.representative_songs),
            musical_traits=clean_text(background.musical_traits),
            source_indices=valid_indices(background.source_indices, count),
        )
    else:
        # 音楽と関係ない動画などでは、推測で埋めないよう各項目も衣装の解析結果も使わない
        message = clean_text(structured.message) or "アーティストを特定できませんでした。"
        fashion_info, background_info = FashionInfo(), BackgroundInfo()
        outfit = MvOutfit(status="skipped", message="アーティストを特定できなかったため")

    return CultureResponse(
        artist=structured.artist.strip(),
        identified=structured.identified,
        message=message,
        fashion=fashion_info,
        background=background_info,
        mv_outfit=outfit,
        sources=research.sources,
        search_suggestions_html=research.search_suggestions_html,
        web_search_queries=research.web_search_queries,
        model=model,
    )


class CultureService:
    """カルチャー情報の取得のユースケースを担うサービス層。"""

    def __init__(
        self, settings: Settings | None = None, client: genai.Client | None = None
    ) -> None:
        # client はテストでフェイクに差し替えるためのもの。None なら共有クライアント(ADC)を使う
        self._settings = settings or get_settings()
        self._client = client

    async def research(self, video: VideoInfo) -> CultureResponse:
        """動画のアーティストを調べ、ファッション・経歴・MV の衣装を整理して返す。"""
        try:
            client = self._client or get_media_client()
        except Exception as exc:
            raise CultureError(f"Gemini のクライアントを作れませんでした: {exc}") from exc

        timeout = self._settings.culture_timeout
        outfit_task: asyncio.Task[MvOutfit] | None = None
        try:
            async with asyncio.timeout(timeout):
                # 映像の解析は Web の調査と並行に走らせる
                outfit_task = asyncio.create_task(self._analyze_video(client, video))
                research = await self._research_web(client, video)
                structured = await self._structure(client, video, research)
                outfit = await outfit_task
        except TimeoutError as exc:
            logger.warning("カルチャー情報の取得がタイムアウトしました(%s 秒)", timeout)
            raise CultureTimeoutError(
                f"カルチャー情報の取得が {timeout:g} 秒以内に終わりませんでした。"
                "時間をおいて再度お試しください。"
            ) from exc
        finally:
            # Web の調査が失敗したら、映像の解析も止める(無駄な課金を避けるため)
            if outfit_task is not None and not outfit_task.done():
                outfit_task.cancel()

        return build_response(research, structured, outfit, self._settings.culture_model)

    async def _research_web(self, client: genai.Client, video: VideoInfo) -> WebResearch:
        try:
            research = await grounded_research(
                client, self._settings.culture_model, build_research_prompt(video)
            )
        except Exception as exc:
            logger.warning("Web での調査に失敗しました: %s", type(exc).__name__)
            raise to_culture_error(exc, "Web での調査") from exc

        if not research.text.strip():
            raise CultureError("Web での調査結果が空でした。")
        return research

    async def _structure(
        self, client: genai.Client, video: VideoInfo, research: WebResearch
    ) -> StructuredCulture:
        try:
            response = await client.aio.models.generate_content(
                model=self._settings.culture_model,
                contents=build_structure_prompt(video, research.text),
                config=types.GenerateContentConfig(
                    system_instruction=_STRUCTURE_INSTRUCTION,
                    response_mime_type="application/json",
                    response_schema=StructuredCulture,
                    automatic_function_calling=NO_AFC,
                    temperature=0,
                ),
            )
        except Exception as exc:
            logger.warning("調査結果の整理に失敗しました: %s", type(exc).__name__)
            raise to_culture_error(exc, "調査結果の整理") from exc

        structured = response.parsed
        if not isinstance(structured, StructuredCulture):
            raise CultureError("調査結果の整理結果を解釈できませんでした。")
        return structured

    async def _analyze_video(self, client: genai.Client, video: VideoInfo) -> MvOutfit:
        """MV の映像から衣装を読み取る。失敗しても例外にせず unavailable を返す。"""
        unavailable = MvOutfit(
            status="unavailable",
            message=(
                "MV の映像を解析できませんでした。"
                "公開されていない動画や年齢制限のある動画は解析できません。"
            ),
        )
        try:
            response = await client.aio.models.generate_content(
                model=self._settings.culture_model,
                contents=[types.Content(role="user", parts=build_outfit_parts(video.url))],
                config=types.GenerateContentConfig(
                    system_instruction=_OUTFIT_INSTRUCTION,
                    response_mime_type="application/json",
                    response_schema=VideoOutfitAnalysis,
                    automatic_function_calling=NO_AFC,
                    media_resolution=types.MediaResolution.MEDIA_RESOLUTION_LOW,
                ),
            )
        except Exception as exc:
            logger.warning("MV の映像を解析できませんでした: %s", type(exc).__name__)
            return unavailable

        analysis = response.parsed
        if not isinstance(analysis, VideoOutfitAnalysis):
            return unavailable
        return MvOutfit(
            status="ok",
            looks=[
                OutfitLook(
                    label=look.label,
                    items=[OutfitItem(**item.model_dump()) for item in look.items],
                )
                for look in analysis.looks
            ],
        )


def get_culture_service() -> CultureService:
    """FastAPI の Depends 用ファクトリ。テスト時は override して差し替える。"""
    return CultureService()
