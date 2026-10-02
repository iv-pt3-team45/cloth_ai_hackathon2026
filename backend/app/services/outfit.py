"""手持ちの服からのコーデ提案と、マネキンに着せた画像の生成(spec 011)。

1. 提案: 手持ちの服(spec 010 の保存先)・MV・カルチャー・ライブ・天気を Gemini に渡し、
   手持ちの服の中から 1 コーデを構造化出力で受け取る。手持ちに無い服の id は捨てる。
2. 画像: マネキン画像と、提案に使う服の**写真そのもの**を
   Nano Banana 2 Flash Lite(IMAGE_MODEL)に渡し、マネキンに着せた画像を生成する。
   生成画像は spec 003 と同じ created_images/ に保存する。

カルチャー情報・ライブ情報はリクエストで受け取るだけで保存しない(spec 008 / 009 の方針)。
"""

import asyncio
import base64
import logging
from pathlib import Path

from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from app.core.config import Settings, get_settings
from app.schemas.culture import CultureResponse
from app.schemas.live import LiveCandidate, LiveWeather
from app.schemas.outfit import OutfitImageResponse, OutfitSuggestion, SuggestedCloth
from app.schemas.youtube import VideoInfo
from app.services.cloth_index import ClothItem
from app.services.grounding import NO_AFC, clean_list, clean_text, is_quota_error
from app.services.media import build_file_name, get_media_client, save_media
from app.services.wardrobe_registry import to_registered
from app.services.wardrobe_store import (
    LocalWardrobeStore,
    StoredCloth,
    StoredEntry,
    WardrobeStore,
)

logger = logging.getLogger(__name__)

_MIME_BY_SUFFIX = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}

_SUGGEST_INSTRUCTION = """\
あなたはプロのスタイリストです。利用者が行くライブに合わせて、
利用者が持っている服(手持ちの服)だけで、おすすめのコーディネートを 1 つ提案してください。

- 使う服は「手持ちの服」の一覧にある服だけにすること。
  一覧の id をそのまま items の id に入れること。
  一覧に無い服(買い足す服・持っていない小物)は絶対に提案しないこと。
- トップスとボトムス(またはワンピース)を基本に、必要なら上着・靴・小物を手持ちから足すこと。
  同じ役割の服を重ねないこと。
  role には「トップス」「ボトムス」「アウター」「靴」「小物」などを書くこと。
- 当日の天気・気温と、服の季節・暖かさを合わせること。会場が屋内か屋外かも考えること。
- アーティストのファッションの傾向や MV の衣装の雰囲気を取り入れ、ライブの場面に合わせること
  (使う場面が「ライブ・フェス」の服を優先する)。
- reason(服ごとの理由)と points(全体のポイント)は具体的に書くこと。日本語で書くこと。
"""


class OutfitError(RuntimeError):
    """コーデ提案・画像の生成に失敗した。ルータが 502 に変換する。"""


class OutfitInputError(OutfitError):
    """手持ちの服が無い / 手持ちに無い服が指定された。ルータが 400 に変換する。"""


class OutfitQuotaError(OutfitError):
    """Gemini のクォータ超過。ルータが 503 に変換する。"""


class OutfitTimeoutError(OutfitError):
    """待ち時間の上限を超えた。ルータが 504 に変換する。"""


# --- モデルの構造化出力(API の契約とは分ける) ------------------------------


class _SuggestedItemOutput(BaseModel):
    id: str = Field(description="手持ちの服の id(一覧の id をそのまま)")
    role: str = Field(description="コーデの中の役割(トップス・ボトムス・アウター・靴・小物など)")
    reason: str = Field(description="この服を選んだ理由")


class _OutfitOutput(BaseModel):
    title: str = Field(description="コーデの名前")
    summary: str = Field(description="コーデ全体の説明(2〜3 文)")
    points: list[str] = Field(description="天気・場面・アーティストらしさなどのポイント")
    items: list[_SuggestedItemOutput] = Field(description="使う手持ちの服")


# --- 手持ちの服 --------------------------------------------------------------

Owned = dict[str, tuple[StoredCloth, StoredEntry]]


def load_owned(store: WardrobeStore) -> Owned:
    """手持ちの服を id → (服, その服が写った写真の記録) にする。"""
    return {item.id: (item, entry) for entry in store.list_entries() for item in entry.items}


def describe_item(item: ClothItem) -> str:
    """服 1 点の属性を 1 行にする(空の項目は書かない)。"""

    def join(values: list[str]) -> str:
        return "・".join(values)

    parts = [
        item.category,
        f"色: {join(item.colors)}" if item.colors else "",
        f"素材: {item.material}" if item.material else "",
        f"形: {item.shape}" if item.shape else "",
        f"柄: {item.pattern}" if item.pattern else "",
        f"系統: {item.style}" if item.style else "",
        f"季節: {join(item.seasons)}" if item.seasons else "",
        f"暖かさ: {item.warmth}" if item.warmth else "",
        f"場面: {join(item.occasions)}" if item.occasions else "",
        f"特徴: {item.notes}" if item.notes else "",
    ]
    return " / ".join(p for p in parts if p)


def label_item(item: ClothItem) -> str:
    """写真の中のどの服かを示す短い名前(例: Tシャツ(ピンク・黄色))。"""
    return f"{item.category}({'・'.join(item.colors)})" if item.colors else item.category


# --- プロンプトの組み立て --------------------------------------------------


def weather_text(weather: LiveWeather) -> str:
    """当日の天気をプロンプト用の 1 行にする。"""
    if weather.kind == "not_yet":
        return "予報はまだ出ていない(季節と会場から考える)"
    if weather.kind not in ("actual", "forecast"):
        return "不明(季節と会場から考える)"
    parts = [
        weather.summary,
        f"最高 {weather.high_c:g}℃" if weather.high_c is not None else "",
        f"最低 {weather.low_c:g}℃" if weather.low_c is not None else "",
        f"降水確率 {weather.precipitation_chance}%"
        if weather.precipitation_chance is not None
        else "",
    ]
    label = "実績" if weather.kind == "actual" else "予報"
    return f"{' / '.join(p for p in parts if p) or '不明'}({label})"


def _culture_lines(culture: CultureResponse | None) -> list[str]:
    if culture is None or not culture.identified:
        return ["- 取得できていない(MV の情報から考える)"]
    fashion, background = culture.fashion, culture.background
    lines = [f"- アーティスト: {culture.artist}"]
    if fashion.styles:
        lines.append(f"- ファッションのスタイル: {'、'.join(fashion.styles)}")
    if fashion.colors:
        lines.append(f"- よく使う色: {'、'.join(fashion.colors)}")
    if fashion.items:
        lines.append(f"- 定番のアイテム: {'、'.join(fashion.items)}")
    if fashion.worldview:
        lines.append(f"- ビジュアルの世界観: {fashion.worldview}")
    if culture.mv_outfit.status == "ok":
        for look in culture.mv_outfit.looks:
            clothes = "、".join(
                f"{i.category}({'・'.join(i.colors)} / {i.style})" for i in look.items
            )
            lines.append(f"- この MV の衣装「{look.label}」: {clothes}")
    if background.genres:
        lines.append(f"- 音楽ジャンル: {'、'.join(background.genres)}")
    if background.summary:
        lines.append(f"- 概要: {background.summary}")
    return lines


def build_suggest_prompt(
    owned: Owned, video: VideoInfo, culture: CultureResponse | None, live: LiveCandidate
) -> str:
    """① 提案のプロンプト。"""
    clothes = "\n".join(
        f"- id={cloth_id}: {describe_item(item)}" for cloth_id, (item, _) in owned.items()
    )
    venue = live.venue + (f"({live.location})" if live.location else "")
    live_lines = [
        f"- ライブ名: {live.live_name or '不明'}",
        f"- 会場: {venue or '不明'}",
        f"- 日付: {live.date.isoformat() if live.date else '不明'}",
        f"- 当日の天気: {weather_text(live.weather)}",
    ]
    culture_text = "\n".join(_culture_lines(culture))
    return (
        f"# 手持ちの服(この中からだけ選ぶ)\n{clothes}\n\n"
        f"# MV\n- 曲名: {video.song_title}\n- アーティスト: {video.artist}\n"
        f"- 動画タイトル: {video.title}\n\n"
        f"# アーティストのカルチャー情報\n{culture_text}\n\n"
        f"# 行くライブ\n" + "\n".join(live_lines)
    )


def build_image_parts(
    mannequin: tuple[bytes, str], photos: list[tuple[bytes, str, list[str]]], title: str
) -> list[types.Part]:
    """② 画像の生成の入力。1 枚目にマネキン、続けて服の写真(同じ写真は 1 回)、最後に指示文。

    服の見た目は写真から再現させる。指示文には、写真の番号とその写真のどの服を使うかだけを書く
    (1 枚の写真に複数の服が写っていることがあるため)。
    """
    parts = [types.Part.from_bytes(data=mannequin[0], mime_type=mannequin[1])]
    lines = []
    for number, (data, mime_type, labels) in enumerate(photos, start=2):
        parts.append(types.Part.from_bytes(data=data, mime_type=mime_type))
        lines.append(f"- 画像 {number} の写真から: {'、'.join(labels)}")
    instruction = (
        "1 枚目の画像は白いマネキンです。2 枚目以降は、利用者が実際に持っている服の写真です。\n"
        f"マネキンに、次の服をそのまま着せた写真を 1 枚作ってください"
        f"{f'(コーデ名: {title})' if title else ''}。\n" + "\n".join(lines) + "\n\n条件:\n"
        "- 服は写真の色・柄・形・素材感・プリントをできるだけ忠実に再現すること。\n"
        "- 写真に無い服や小物を足さないこと。\n"
        "- 1 枚の写真に複数の服が写っている場合は、指定した服だけを使うこと。\n"
        "- マネキンの姿勢・台・背景(白い布と床)・画角は 1 枚目の画像のまま保つこと。"
    )
    parts.append(types.Part.from_text(text=instruction))
    return parts


def extract_image(response: types.GenerateContentResponse) -> tuple[bytes, str] | None:
    """応答から最初の画像を取り出す。無ければ None。"""
    candidates = response.candidates or []
    content = candidates[0].content if candidates else None
    for part in (content.parts or []) if content else []:
        inline = part.inline_data
        if inline and inline.data:
            return inline.data, inline.mime_type or "image/png"
    return None


def _to_error(exc: Exception, action: str) -> OutfitError:
    if isinstance(exc, OutfitError):
        return exc
    if is_quota_error(exc):
        return OutfitQuotaError(
            "Gemini のクォータ(利用上限)を超えました。時間をおいて再度お試しください。"
        )
    return OutfitError(f"{action}に失敗しました: {exc}")


class OutfitService:
    """コーデ提案と画像の生成のユースケースを担うサービス層。"""

    def __init__(
        self,
        settings: Settings | None = None,
        store: WardrobeStore | None = None,
        client: genai.Client | None = None,
    ) -> None:
        # store / client はテストで差し替えるためのもの。手持ちの服は spec 010 と同じ保存先
        self._settings = settings or get_settings()
        self._store = store or LocalWardrobeStore(self._settings.cloth_index_file)
        self._client = client

    def _get_client(self) -> genai.Client:
        try:
            return self._client or get_media_client()
        except Exception as exc:
            raise OutfitError(f"Gemini のクライアントを作れませんでした: {exc}") from exc

    async def suggest(
        self, video: VideoInfo, culture: CultureResponse | None, live: LiveCandidate
    ) -> OutfitSuggestion:
        """手持ちの服の中から 1 コーデを提案する。"""
        owned = load_owned(self._store)
        if not owned:
            raise OutfitInputError(
                "手持ちの服が登録されていません。手持ちの服タブで登録してください。"
            )
        client = self._get_client()
        model = self._settings.outfit_model
        timeout = self._settings.outfit_timeout
        try:
            async with asyncio.timeout(timeout):
                response = await client.aio.models.generate_content(
                    model=model,
                    contents=build_suggest_prompt(owned, video, culture, live),
                    config=types.GenerateContentConfig(
                        system_instruction=_SUGGEST_INSTRUCTION,
                        response_mime_type="application/json",
                        response_schema=_OutfitOutput,
                        temperature=0.7,
                        automatic_function_calling=NO_AFC,
                    ),
                )
        except TimeoutError as exc:
            raise OutfitTimeoutError(
                f"コーデの提案が {timeout:g} 秒以内に終わりませんでした。"
                "時間をおいて再度お試しください。"
            ) from exc
        except Exception as exc:
            logger.warning("コーデの提案に失敗しました: %s", type(exc).__name__)
            raise _to_error(exc, "コーデの提案") from exc

        output = response.parsed
        if not isinstance(output, _OutfitOutput):
            raise OutfitError("コーデの提案を解釈できませんでした。")

        items: list[SuggestedCloth] = []
        seen: set[str] = set()
        excluded = 0
        for suggested in output.items:
            cloth_id = suggested.id.strip()
            if cloth_id in seen:
                continue
            if cloth_id not in owned:
                # 手持ちに無い服は提案に含めない(要件)
                excluded += 1
                continue
            seen.add(cloth_id)
            _, entry = owned[cloth_id]
            registered = next(c for c in to_registered(entry) if c.id == cloth_id)
            items.append(
                SuggestedCloth.model_validate(
                    {
                        **registered.model_dump(),
                        "role": clean_text(suggested.role),
                        "reason": suggested.reason.strip(),
                    }
                )
            )
        if excluded:
            logger.info("手持ちに無い服を提案から除きました: %d 点", excluded)
        if not items:
            raise OutfitError("手持ちの服からコーデを作れませんでした。もう一度お試しください。")

        return OutfitSuggestion(
            title=output.title.strip(),
            summary=output.summary.strip(),
            points=clean_list(output.points),
            items=items,
            excluded_count=excluded,
            model=model,
        )

    async def generate_image(self, item_ids: list[str], title: str) -> OutfitImageResponse:
        """提案の服の写真をマネキンに着せた画像を生成し、保存して返す。"""
        owned = load_owned(self._store)
        unknown = [cloth_id for cloth_id in item_ids if cloth_id not in owned]
        if unknown:
            raise OutfitInputError("手持ちに無い服が指定されました。提案し直してください。")

        mannequin = self._read_mannequin()
        photos = self._read_photos(item_ids, owned)
        client = self._get_client()
        model = self._settings.image_model
        timeout = self._settings.media_generation_timeout
        try:
            async with asyncio.timeout(timeout):
                response = await client.aio.models.generate_content(
                    model=model,
                    contents=[
                        types.Content(
                            role="user", parts=build_image_parts(mannequin, photos, title)
                        )
                    ],
                    config=types.GenerateContentConfig(
                        response_modalities=["TEXT", "IMAGE"],
                        automatic_function_calling=NO_AFC,
                    ),
                )
        except TimeoutError as exc:
            raise OutfitTimeoutError(
                f"画像の生成が {timeout:g} 秒以内に終わりませんでした。"
                "時間をおいて再度お試しください。"
            ) from exc
        except Exception as exc:
            logger.warning("コーデの画像の生成に失敗しました: %s", type(exc).__name__)
            raise _to_error(exc, "画像の生成") from exc

        image = extract_image(response)
        if image is None:
            # 同じ入力でも時々画像が返らないことがある(T-08)。原因を追えるよう終了理由を残す
            candidates = response.candidates or []
            logger.warning(
                "コーデの画像が返りませんでした: finish_reason=%s",
                candidates[0].finish_reason if candidates else None,
            )
            raise OutfitError("モデルが画像を返しませんでした。もう一度お試しください。")
        data, mime_type = image
        path = save_media(
            data,
            self._settings.created_images_path,
            build_file_name("outfit", mime_type, ".png"),
        )
        return OutfitImageResponse(
            mime_type=mime_type,
            data=base64.b64encode(data).decode(),
            file_name=path.name,
            model=model,
        )

    def _read_mannequin(self) -> tuple[bytes, str]:
        path: Path = self._settings.outfit_mannequin_file
        if not path.is_file():
            raise OutfitError(
                f"マネキン画像が見つかりません({path})。OUTFIT_MANNEQUIN_PATH を確認してください。"
            )
        return path.read_bytes(), _MIME_BY_SUFFIX.get(path.suffix.lower(), "image/jpeg")

    def _read_photos(self, item_ids: list[str], owned: Owned) -> list[tuple[bytes, str, list[str]]]:
        """提案の服が写った写真を、指定の順に重複なく読む(写真ごとに使う服の名前を添える)。"""
        labels_by_image: dict[str, list[str]] = {}
        for cloth_id in item_ids:
            item, entry = owned[cloth_id]
            labels = labels_by_image.setdefault(entry.image, [])
            if label_item(item) not in labels:
                labels.append(label_item(item))

        photos = []
        for image, labels in labels_by_image.items():
            found = self._store.read_image(image)
            if found is None:
                raise OutfitError(f"服の写真が見つかりません({image})。")
            photos.append((found[0], found[1], labels))
        return photos


def get_outfit_service() -> OutfitService:
    """FastAPI の Depends 用ファクトリ。テスト時は override して差し替える。"""
    return OutfitService()
