"""ライブ情報を Gemini + Google 検索で調べる(spec 009)。

1 回の検索で Gemini を 2 回呼ぶ(spec 008 と同じ形)。

1. 調べる: Google 検索ありで、条件に合うライブと当日の天気を自由文で調べさせる。
2. 整理する: 検索なしで、1. の本文を JSON(最大 3 件)に整理させる。

天気は「推測で埋めない」ため、モデルの出力をそのまま使わず、あり得ない値
(未来の日付の実績、予報の出ない先の日付の値)をサーバで取り除く。
結果は保存しない(グラウンディング結果の保存は利用規約上の問題になるおそれがあるため)。
"""

import asyncio
import datetime as dt
import logging
from collections.abc import Callable

from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from app.core.config import Settings, get_settings
from app.schemas.live import LiveCandidate, LiveSearchResponse, LiveWeather, WeatherKind
from app.services.grounding import (
    NO_AFC,
    WebResearch,
    clean_text,
    grounded_research,
    is_quota_error,
    valid_indices,
)
from app.services.input_guard import UNTRUSTED_INPUT_RULE, ensure_safe, wrap_user_input
from app.services.media import get_media_client

logger = logging.getLogger(__name__)

# 日本時間(夏時間が無いため固定のオフセットでよい)
JST = dt.timezone(dt.timedelta(hours=9), "JST")
MAX_CANDIDATES = 3
_NOT_FOUND = "該当するライブが見つかりませんでした。"
# 天気の予報が出るのはおよそ 2 週間先まで。それより先の公演は「予報はまだありません」にする
FORECAST_HORIZON_DAYS = 14
_WEATHER_KINDS: dict[str, WeatherKind] = {
    "actual": "actual",
    "forecast": "forecast",
    "not_yet": "not_yet",
    "unknown": "unknown",
}

_STRUCTURE_INSTRUCTION = """\
あなたは調査メモを整理する編集者です。調査メモの内容を、指定された JSON の形に整理してください。

- メモに書かれていない情報を足さないこと。「不明」の項目は空文字(数値は null)にすること。
- candidates は最大 3 件。条件に合う順に並べること。
  見つからなかった場合は found を false にし、message に理由を書くこと。
- date は YYYY-MM-DD 形式にすること。分からなければ空文字にすること。
- weather.kind は、実際の天気なら actual、予報なら forecast、予報がまだ出ていないなら not_yet、
  分からなければ unknown にすること。
- 気温は数値(℃)、降水確率は 0〜100 の整数(%)にすること。
- メモ中の [1] [2] のような番号は出典番号。
  候補ごとに、根拠にした番号を source_indices に入れること。
- 天気の根拠にした出典番号は weather.source_indices に入れること。
  天気の文に出典番号が付いていない場合、その天気は検索で確認できていないため、
  weather.source_indices を空にし、kind を unknown にすること。
"""


class LiveSearchError(RuntimeError):
    """ライブ情報の検索に失敗したときの例外。ルータが 502 に変換する。"""


class LiveSearchQuotaError(LiveSearchError):
    """Gemini のクォータ超過。ルータが 503 に変換する。"""


class LiveSearchTimeoutError(LiveSearchError):
    """待ち時間の上限を超えた。ルータが 504 に変換する。"""


# --- モデルの構造化出力(API の契約とは分ける) ------------------------------


class _WeatherOutput(BaseModel):
    # 想定外の値で応答全体の解釈が失敗しないよう、種類は文字列で受けてサーバで検証する
    kind: str = Field(
        description="actual(実績)/ forecast(予報)/ not_yet(予報はまだ無い)/ unknown(不明)"
    )
    summary: str = Field(description="天気の概況(例: 晴れ時々曇り)。不明なら空文字")
    high_c: float | None = Field(description="最高気温(℃)。不明なら null")
    low_c: float | None = Field(description="最低気温(℃)。不明なら null")
    precipitation_chance: int | None = Field(description="降水確率(%)。不明なら null")
    source_indices: list[int] = Field(description="天気の根拠にした出典番号([n] の n)")


class _CandidateOutput(BaseModel):
    artist: str = Field(description="アーティスト名。アーティストが指定済みなら空文字")
    live_name: str = Field(description="ライブ名・ツアー名・公演名")
    venue: str = Field(description="会場名")
    location: str = Field(description="会場の所在地(都道府県・市区町村)")
    date: str = Field(description="公演日(YYYY-MM-DD)。不明なら空文字")
    weather: _WeatherOutput
    source_indices: list[int] = Field(description="根拠にした出典番号([n] の n)")


class LiveSearchOutput(BaseModel):
    """2. 整理する の出力。"""

    found: bool = Field(description="条件に合うライブが見つかったか")
    message: str = Field(description="見つからなかった場合の理由。見つかったら空文字")
    candidates: list[_CandidateOutput] = Field(description="ライブの候補(最大 3 件)")


# --- プロンプト ------------------------------------------------------------


def today_jst() -> dt.date:
    """今日の日付(日本時間)。"""
    return dt.datetime.now(JST).date()


def build_research_prompt(
    query: str, date: dt.date | None, artist: str | None, today: dt.date
) -> str:
    """1. 調べる のプロンプト。今日の日付を渡し、天気が実績か予報かを判断させる。"""
    if artist:
        # 利用者の入力は区切って、データとして扱わせる(spec 037)
        artist_line = f"{wrap_user_input(artist)}(このアーティストの公演だけを対象にしてください)"
    else:
        artist_line = "指定なし(条件からアーティストも特定してください)"
    items = [] if artist else ["アーティスト名"]
    items += [
        "ライブ名(ツアー名・公演名)",
        "会場名と所在地(都道府県・市区町村)",
        "公演日(1 候補につき 1 日。ツアーの場合は、条件に近い日程を別々の候補にする)",
        "当日の会場付近の天気(天気の概況・最高気温・最低気温・降水確率)\n"
        "   - 候補ごとに、公演日と会場の所在地で Google 検索して調べること"
        "(例: 「2023年6月3日 さいたま市 天気」)\n"
        "   - 公演日が今日より前: その日の実際の天気(実績)\n"
        "   - 公演日が今日以降で予報が出ている: 予報\n"
        "   - 予報がまだ出ていない: 「予報はまだありません」\n"
        "   - 検索で確認できなかった場合: 「不明」(気温などを推測で書かない)",
    ]
    numbered = "\n".join(f"{i}. {item}" for i, item in enumerate(items, start=1))
    return f"""\
あなたはライブ・コンサートの情報に詳しいリサーチャーです。
次の条件に当てはまるライブ(公演)を Google 検索で調べ、
候補を最大 {MAX_CANDIDATES} 件、日本語でまとめてください。

# 条件
- アーティスト: {artist_line}
- ライブ情報: {wrap_user_input(query) if query else "指定なし"}
- 公演日: {date.isoformat() if date else "指定なし"}
- 今日の日付: {today.isoformat()}(日本時間)

# 候補ごとに書くこと
{numbered}

条件に当てはまる公演が見つからなければ「見つかりませんでした」とその理由を書いてください。
{UNTRUSTED_INPUT_RULE}
Web で確認できた内容だけを書き、分からない項目は「不明」と書いてください。推測で埋めないでください。
"""


def build_structure_prompt(research_text: str, artist: str | None) -> str:
    """2. 整理する のプロンプト。"""
    note = (
        f"# アーティスト\n指定済み({artist})。各候補の artist は空文字にすること。\n\n"
        if artist
        else ""
    )
    return f"{note}# 調査メモ\n{research_text}"


# --- 整え方 ----------------------------------------------------------------


def parse_date(value: str) -> dt.date | None:
    """`YYYY-MM-DD`(`YYYY/MM/DD` も可)を日付にする。解釈できなければ None。"""
    try:
        return dt.date.fromisoformat(value.strip().replace("/", "-"))
    except ValueError:
        return None


def normalize_weather(
    weather: _WeatherOutput, date: dt.date | None, today: dt.date, source_count: int
) -> LiveWeather:
    """天気を整える。あり得ない値・根拠の無い値は、推測で埋めないよう取り除く。"""
    kind = _WEATHER_KINDS.get(weather.kind.strip().lower(), "unknown")

    if date is not None:
        if date > today + dt.timedelta(days=FORECAST_HORIZON_DAYS):
            # 予報がまだ出ない先の日付の値は根拠が無い
            return LiveWeather(kind="not_yet")
        if kind == "actual" and date > today:
            # 未来の日付の「実績」はあり得ない
            return LiveWeather(kind="unknown")

    if kind in ("not_yet", "unknown"):
        return LiveWeather(kind=kind)
    if not valid_indices(weather.source_indices, source_count):
        # 出典の無い天気は検索で確認できていない(モデルの推測の可能性がある)
        return LiveWeather(kind="unknown")

    chance = weather.precipitation_chance
    if kind == "actual" or chance is None or not 0 <= chance <= 100:
        # 降水確率は予報の値。実績では使わない
        chance = None
    return LiveWeather(
        kind=kind,
        summary=clean_text(weather.summary),
        high_c=weather.high_c,
        low_c=weather.low_c,
        precipitation_chance=chance,
    )


def build_response(
    research: WebResearch,
    output: LiveSearchOutput,
    artist: str | None,
    today: dt.date,
    model: str,
) -> LiveSearchResponse:
    """2 つの結果を API のレスポンスにまとめる。"""
    count = len(research.sources)
    candidates: list[LiveCandidate] = []
    for raw in output.candidates:
        live_name, venue = clean_text(raw.live_name), clean_text(raw.venue)
        date = parse_date(raw.date)
        if not (live_name or venue or date):
            # 中身の無い候補は捨てる
            continue
        candidates.append(
            LiveCandidate(
                index=len(candidates) + 1,
                # アーティストが指定済みなら取得しない(要件)
                artist=None if artist else (clean_text(raw.artist) or None),
                live_name=live_name,
                venue=venue,
                location=clean_text(raw.location),
                date=date,
                weather=normalize_weather(raw.weather, date, today, count),
                # 天気の出典もあわせて候補の出典として示す
                source_indices=valid_indices(
                    [*raw.source_indices, *raw.weather.source_indices], count
                ),
            )
        )
        if len(candidates) == MAX_CANDIDATES:
            break

    found = output.found and bool(candidates)
    return LiveSearchResponse(
        artist=artist or "",
        found=found,
        message="" if found else (clean_text(output.message) or _NOT_FOUND),
        candidates=candidates if found else [],
        sources=research.sources,
        search_suggestions_html=research.search_suggestions_html,
        web_search_queries=research.web_search_queries,
        model=model,
    )


def to_live_error(exc: Exception, action: str) -> LiveSearchError:
    """Gemini の例外を業務例外に変換する。"""
    if isinstance(exc, LiveSearchError):
        return exc
    if is_quota_error(exc):
        return LiveSearchQuotaError(
            "Gemini のクォータ(利用上限)を超えました。時間をおいて再度お試しください。"
        )
    return LiveSearchError(f"{action}に失敗しました: {exc}")


class LiveService:
    """ライブ情報の検索のユースケースを担うサービス層。"""

    def __init__(
        self,
        settings: Settings | None = None,
        client: genai.Client | None = None,
        today: Callable[[], dt.date] = today_jst,
    ) -> None:
        # client / today はテストで差し替えるためのもの
        self._settings = settings or get_settings()
        self._client = client
        self._today = today

    async def search(
        self, query: str, date: dt.date | None, artist: str | None
    ) -> LiveSearchResponse:
        """条件に合うライブを最大 3 件、当日の天気とともに返す。"""
        # 不審な言い回しは Gemini を呼ぶ前に断る(spec 037)
        ensure_safe(query, "ライブ情報", "live/search")
        artist = (artist or "").strip() or None
        try:
            client = self._client or get_media_client()
        except Exception as exc:
            raise LiveSearchError(f"Gemini のクライアントを作れませんでした: {exc}") from exc

        today = self._today()
        model = self._settings.live_search_model
        timeout = self._settings.live_search_timeout
        try:
            async with asyncio.timeout(timeout):
                research = await self._research(client, query, date, artist, today)
                output = await self._structure(client, research, artist)
        except TimeoutError as exc:
            logger.warning("ライブ情報の検索がタイムアウトしました(%s 秒)", timeout)
            raise LiveSearchTimeoutError(
                f"ライブ情報の検索が {timeout:g} 秒以内に終わりませんでした。"
                "時間をおいて再度お試しください。"
            ) from exc

        return build_response(research, output, artist, today, model)

    async def _research(
        self,
        client: genai.Client,
        query: str,
        date: dt.date | None,
        artist: str | None,
        today: dt.date,
    ) -> WebResearch:
        prompt = build_research_prompt(query, date, artist, today)
        try:
            research = await grounded_research(client, self._settings.live_search_model, prompt)
        except Exception as exc:
            logger.warning("ライブ情報の調査に失敗しました: %s", type(exc).__name__)
            raise to_live_error(exc, "ライブ情報の調査") from exc

        if not research.text.strip():
            raise LiveSearchError("ライブ情報の調査結果が空でした。")
        return research

    async def _structure(
        self, client: genai.Client, research: WebResearch, artist: str | None
    ) -> LiveSearchOutput:
        try:
            response = await client.aio.models.generate_content(
                model=self._settings.live_search_model,
                contents=build_structure_prompt(research.text, artist),
                config=types.GenerateContentConfig(
                    system_instruction=_STRUCTURE_INSTRUCTION,
                    response_mime_type="application/json",
                    response_schema=LiveSearchOutput,
                    automatic_function_calling=NO_AFC,
                    temperature=0,
                ),
            )
        except Exception as exc:
            logger.warning("ライブ情報の整理に失敗しました: %s", type(exc).__name__)
            raise to_live_error(exc, "ライブ情報の整理") from exc

        output = response.parsed
        if not isinstance(output, LiveSearchOutput):
            raise LiveSearchError("ライブ情報の整理結果を解釈できませんでした。")
        return output


def get_live_service() -> LiveService:
    """FastAPI の Depends 用ファクトリ。テスト時は override して差し替える。"""
    return LiveService()
