"""服の画像から属性(素材・形・色・系統・季節・暖かさ・使う場面)を抽出してインデックス化する。

画像 1 枚ごとにモデルへ問い合わせ、構造化出力で属性を受け取る。
結果は 1 つの `index.json` にまとめて保存する(spec 005)。
アプリからの登録(spec 010)も、画像データを渡して同じ解析を使う(`analyze_cloth_bytes`)。
"""

import json
import logging
import re
from collections.abc import Callable, Sequence
from datetime import datetime
from pathlib import Path
from typing import get_args

from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from app.core.config import Settings, get_settings
from app.schemas.wardrobe import Occasion, Season, Warmth
from app.services.grounding import NO_AFC
from app.services.media import get_media_client

logger = logging.getLogger(__name__)

SUPPORTED_SUFFIXES = (".jpg", ".jpeg", ".png", ".webp")

_MIME_BY_SUFFIX = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}

INDEX_FILE_NAME = "index.json"

_INSTRUCTION = """\
あなたはアパレルの商品情報を作成する専門家です。
写真に写っている衣類を見て、服ごとに属性を日本語で記録してください。

- 写っている衣類が複数あれば、items に服ごとに分けて記録すること。
- 靴・帽子・バッグなどの小物も、身につけるものであれば 1 件として記録してよい。
- material(素材)は見た目からの推定でよい。判断できない場合は「不明」と書くこと。
- colors は目立つ順に並べること。
- style(系統)は「カジュアル」「ストリート」「きれいめ」のように一般的な呼び方で書くこと。
- notes にはプリントの文言や装飾など、検索の手がかりになる特徴を書くこと。
- seasons は「春」「夏」「秋」「冬」から、着るのに向いている季節をすべて選ぶこと。
- warmth は「薄手」「普通」「厚手」から 1 つ選ぶこと。
- occasions は「普段着」「きれいめ(食事・オフィス)」「フォーマル」「スポーツ・アウトドア」
  「ライブ・フェス」から、向いている場面をすべて選ぶこと。
- 衣類が写っていない場合は items を空にし、summary にその旨を書くこと。
"""

# 季節・暖かさ・使う場面の選択肢(正は app/schemas/wardrobe.py)
SEASONS: tuple[str, ...] = get_args(Season)
WARMTHS: tuple[str, ...] = get_args(Warmth)
OCCASIONS: tuple[str, ...] = get_args(Occasion)


class ClothIndexError(RuntimeError):
    """インデックス作成に失敗したときの例外。"""


class ClothItem(BaseModel):
    """1 着ぶんの属性。"""

    category: str = Field(description="種類(Tシャツ、パンツ、スニーカーなど)")
    material: str = Field(description="素材(綿、ポリエステル、デニムなど。不明なら「不明」)")
    shape: str = Field(description="形・シルエット(半袖クルーネック、ワイドなど)")
    colors: list[str] = Field(default_factory=list, description="色。目立つ順")
    pattern: str = Field(default="", description="柄(無地、プリント、ストライプなど)")
    style: str = Field(default="", description="系統(カジュアル、ストリートなど)")
    notes: str = Field(default="", description="プリントの文言や装飾などの特徴")
    # 以下は spec 010 で追加。既存の index.json(項目が無い)も既定値で読める。
    # 想定外の値で応答全体の解釈が失敗しないよう文字列で受け、normalize_item() で選択肢に整える
    seasons: list[str] = Field(
        default_factory=list, description="着るのに向いている季節(春 / 夏 / 秋 / 冬 から複数)"
    )
    warmth: str = Field(default="", description="暖かさ(薄手 / 普通 / 厚手 から 1 つ)")
    occasions: list[str] = Field(
        default_factory=list,
        description=(
            "使う場面(普段着 / きれいめ(食事・オフィス)/ フォーマル / "
            "スポーツ・アウトドア / ライブ・フェス から複数)"
        ),
    )


class ClothAnalysis(BaseModel):
    """モデルの構造化出力。"""

    items: list[ClothItem] = Field(default_factory=list, description="写っている衣類")
    summary: str = Field(default="", description="画像全体の説明")


class ClothIndexEntry(BaseModel):
    """インデックスに保存する 1 画像ぶんの記録。"""

    image: str
    items: list[ClothItem] = Field(default_factory=list)
    summary: str = ""
    model: str = ""
    analyzed_at: str = ""


def list_images(directory: Path) -> list[Path]:
    """対象ディレクトリの画像を名前順で返す(画像以外は無視する)。"""
    if not directory.is_dir():
        raise ClothIndexError(f"画像ディレクトリがありません: {directory}")
    return sorted(
        p for p in directory.iterdir() if p.is_file() and p.suffix.lower() in SUPPORTED_SUFFIXES
    )


def guess_mime_type(path: Path) -> str:
    """画像の MIME タイプ。未知の拡張子は JPEG 扱いにする。"""
    return _MIME_BY_SUFFIX.get(path.suffix.lower(), "image/jpeg")


def index_path(output_dir: Path) -> Path:
    """インデックスファイルの保存先。"""
    return output_dir / INDEX_FILE_NAME


def _pick(value: str, choices: Sequence[str]) -> str | None:
    """選択肢に当てはまる値を返す。

    「きれいめ(食事・オフィス)」のような説明つきの値は、括弧の前の語で照合する。
    """
    text = value.strip()
    if text in choices:
        return text
    head = re.split(r"[(（]", text, maxsplit=1)[0].strip()
    return head if head in choices else None


def _pick_many(values: Sequence[str], choices: Sequence[str]) -> list[str]:
    """選択肢に当てはまる値だけを、選択肢の並び順で重複なく返す。"""
    picked = {p for value in values if (p := _pick(value, choices))}
    return [choice for choice in choices if choice in picked]


def normalize_item(item: ClothItem) -> ClothItem:
    """季節・暖かさ・使う場面を選択肢に整える(選択肢の外の値は捨てる)。"""
    return item.model_copy(
        update={
            "seasons": _pick_many(item.seasons, SEASONS),
            "warmth": _pick(item.warmth, WARMTHS) or "",
            "occasions": _pick_many(item.occasions, OCCASIONS),
        }
    )


def analyze_cloth_bytes(
    data: bytes,
    mime_type: str,
    settings: Settings | None = None,
    client: genai.Client | None = None,
) -> ClothAnalysis:
    """画像データ 1 枚を解析して、服ごとの属性を返す(選択肢の項目は整えたもの)。

    Raises:
        ClothIndexError: モデルの呼び出しに失敗した / 応答を解釈できない場合。
            元の例外は `__cause__` に残す(呼び出し側がクォータ超過などを判定できるように)。
    """
    settings = settings or get_settings()
    try:
        client = client or get_media_client()
        response = client.models.generate_content(
            model=settings.cloth_index_model,
            contents=[
                types.Content(
                    role="user",
                    parts=[
                        types.Part.from_bytes(data=data, mime_type=mime_type),
                        types.Part.from_text(text="この画像の衣類の属性を記録してください。"),
                    ],
                )
            ],
            config=types.GenerateContentConfig(
                system_instruction=_INSTRUCTION,
                response_mime_type="application/json",
                response_schema=ClothAnalysis,
                automatic_function_calling=NO_AFC,
            ),
        )
    except Exception as exc:
        raise ClothIndexError(f"解析に失敗しました: {exc}") from exc

    analysis = response.parsed
    if not isinstance(analysis, ClothAnalysis):
        raise ClothIndexError("応答を解釈できませんでした。")
    return analysis.model_copy(update={"items": [normalize_item(i) for i in analysis.items]})


def analyze_cloth_image(
    image: Path,
    settings: Settings | None = None,
    client: genai.Client | None = None,
) -> ClothIndexEntry:
    """画像ファイル 1 枚を解析して属性を返す(spec 005 の CLI 用)。"""
    settings = settings or get_settings()
    try:
        analysis = analyze_cloth_bytes(
            image.read_bytes(), guess_mime_type(image), settings=settings, client=client
        )
    except ClothIndexError as exc:
        raise ClothIndexError(f"{image.name}: {exc}") from exc

    return ClothIndexEntry(
        image=image.name,
        items=analysis.items,
        summary=analysis.summary,
        model=settings.cloth_index_model,
        analyzed_at=datetime.now().astimezone().isoformat(timespec="seconds"),
    )


def _write_json(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_index(output_dir: Path) -> dict[str, ClothIndexEntry]:
    """既存の `index.json` を画像名 → エントリの辞書として読み込む。

    ファイルが無い / 壊れている場合は空の辞書を返す(作り直しになる)。
    """
    path = index_path(output_dir)
    if not path.is_file():
        return {}

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        entries = [ClothIndexEntry.model_validate(e) for e in payload.get("entries", [])]
    except Exception:
        logger.warning("既存の %s を読み込めなかったため作り直します", path.name)
        return {}

    return {entry.image: entry for entry in entries}


def save_index(
    entries: list[ClothIndexEntry], output_dir: Path, source_dir: Path, model: str
) -> Path:
    """インデックスを 1 ファイル(`index.json`)にまとめて保存する。"""
    path = index_path(output_dir)
    _write_json(
        path,
        {
            "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "model": model,
            "source_dir": str(source_dir),
            "count": len(entries),
            "entries": [entry.model_dump() for entry in entries],
        },
    )
    return path


def build_cloth_index(
    source_dir: Path,
    output_dir: Path,
    *,
    force: bool = False,
    settings: Settings | None = None,
    analyze: Callable[[Path], ClothIndexEntry] | None = None,
    on_progress: Callable[[Path, ClothIndexEntry | None, str], None] | None = None,
) -> list[ClothIndexEntry]:
    """ディレクトリ内の画像をまとめてインデックス化する。

    Args:
        source_dir: 画像のあるディレクトリ。
        output_dir: JSON の出力先。
        force: True なら既存の結果があっても作り直す。
        analyze: 解析関数(テストで差し替える)。
        on_progress: 画像ごとに `(画像, 結果, 状態)` で呼ばれる。状態は
            "analyzed" / "skipped" / "failed"。

    Returns:
        保存したエントリの一覧(画像の名前順)。
    """
    settings = settings or get_settings()

    def default_analyze(image: Path) -> ClothIndexEntry:
        return analyze_cloth_image(image, settings=settings)

    analyze_fn = analyze or default_analyze

    known: dict[str, ClothIndexEntry] = {} if force else load_index(output_dir)

    entries: list[ClothIndexEntry] = []
    for image in list_images(source_dir):
        existing = known.get(image.name)
        if existing is not None:
            entries.append(existing)
            if on_progress:
                on_progress(image, existing, "skipped")
            continue

        try:
            entry = analyze_fn(image)
        except ClothIndexError as exc:
            # 1 枚の失敗で全体を止めない
            logger.warning("%s", exc)
            if on_progress:
                on_progress(image, None, "failed")
            continue

        entries.append(entry)
        # 途中で中断しても解析済みが失われないよう、1 枚ごとに書き出す
        save_index(entries, output_dir, source_dir, settings.cloth_index_model)
        if on_progress:
            on_progress(image, entry, "analyzed")

    save_index(entries, output_dir, source_dir, settings.cloth_index_model)
    return entries
