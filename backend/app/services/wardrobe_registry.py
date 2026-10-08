"""手持ちの服の写真の登録(spec 010)のユースケース。

- 解析: 写真 1 枚を Gemini で解析して服ごとの属性にする(**保存しない**)。
- 保存: 利用者が確認・修正した属性と写真を `WardrobeStore` に保存する。
- 一覧・削除・写真の読み出し。

解析(spec 005 の `analyze_cloth_bytes`)と保存(`WardrobeStore`)を組み合わせ、
例外を業務例外に変換する。ルータが HTTP ステータスに対応付ける。
"""

import base64
import binascii
import logging
from datetime import datetime

from google import genai

from app.core.config import Settings, get_settings
from app.schemas.wardrobe import (
    AnalyzeResponse,
    ClothAttributes,
    RegisteredCloth,
    RegisterRequest,
    WardrobeImage,
)
from app.services.cloth_index import ClothIndexError, ClothItem, analyze_cloth_bytes, normalize_item
from app.services.grounding import is_quota_error
from app.services.wardrobe_store import (
    StoredEntry,
    WardrobeStore,
    WardrobeStoreError,
    create_wardrobe_store,
)

logger = logging.getLogger(__name__)


class WardrobeError(RuntimeError):
    """手持ちの服の登録に失敗した(解析・保存)。ルータが 502 に変換する。"""


class WardrobeInputError(WardrobeError):
    """写真のデータが不正(base64 が不正、中身が指定の形式ではない)。ルータが 400 に変換する。"""


class WardrobeImageTooLargeError(WardrobeInputError):
    """写真が上限を超えている。ルータが 413 に変換する。"""


class WardrobeNotFoundError(WardrobeError):
    """削除する服 / 読み出す写真が無い。ルータが 404 に変換する。"""


class WardrobeQuotaError(WardrobeError):
    """Gemini のクォータ超過。ルータが 503 に変換する。"""


def _matches_format(data: bytes, mime_type: str) -> bool:
    """先頭のバイトが、指定された形式の画像のものか。"""
    if mime_type == "image/jpeg":
        return data.startswith(b"\xff\xd8\xff")
    if mime_type == "image/png":
        return data.startswith(b"\x89PNG\r\n\x1a\n")
    if mime_type == "image/webp":
        return data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    return False


def decode_image(image: WardrobeImage, max_bytes: int) -> bytes:
    """base64 の写真をバイト列に戻し、大きさと形式を確かめる。"""
    limit_mb = max_bytes / (1024 * 1024)
    too_large = WardrobeImageTooLargeError(
        f"写真が大きすぎます。{limit_mb:g} MB 以下の写真を選んでください。"
    )
    # デコードする前に、base64 の長さ(元の約 4/3 倍)でも大きすぎるものを弾く
    if len(image.data) > max_bytes * 4 // 3 + 4:
        raise too_large
    try:
        data = base64.b64decode(image.data, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise WardrobeInputError("写真のデータを読み取れませんでした(base64 が不正です)。") from exc
    if len(data) > max_bytes:
        raise too_large
    if not _matches_format(data, image.mime_type):
        raise WardrobeInputError(
            f"写真の中身が指定の形式({image.mime_type})ではありません。"
            "jpg / png / webp の写真を選んでください。"
        )
    return data


def to_attributes(item: ClothItem) -> ClothAttributes:
    """保存・解析の形(ClothItem)から API の形にする。暖かさの空文字は null にする。"""
    item = normalize_item(item)
    values = item.model_dump(include=set(ClothAttributes.model_fields))
    return ClothAttributes.model_validate({**values, "warmth": item.warmth or None})


def to_cloth_item(attributes: ClothAttributes) -> ClothItem:
    """API の形から保存の形にする。季節・使う場面は選択肢の順に並べ直す。"""
    values = attributes.model_dump()
    return normalize_item(ClothItem.model_validate({**values, "warmth": attributes.warmth or ""}))


def to_registered(entry: StoredEntry) -> list[RegisteredCloth]:
    """保存した写真 1 枚ぶんを、登録済みの服の一覧にする。"""
    try:
        registered_at: datetime | None = datetime.fromisoformat(entry.analyzed_at)
    except ValueError:
        registered_at = None
    return [
        RegisteredCloth.model_validate(
            {
                **to_attributes(item).model_dump(),
                "id": item.id,
                "image": entry.image,
                "registered_at": registered_at,
            }
        )
        for item in entry.items
    ]


class WardrobeService:
    """手持ちの服の登録のユースケースを担うサービス層。"""

    def __init__(
        self,
        settings: Settings | None = None,
        store: WardrobeStore | None = None,
        client: genai.Client | None = None,
    ) -> None:
        # store / client はテストで差し替えるためのもの。
        # 保存先は WARDROBE_STORAGE で決まる(既定は CLOTH_INDEX_PATH。spec 036)。
        # チャットのエージェントも同じ保存先を参照する
        self._settings = settings or get_settings()
        self._store = store or create_wardrobe_store(self._settings)
        self._client = client

    def analyze(self, image: WardrobeImage) -> AnalyzeResponse:
        """写真 1 枚を解析して、服ごとの属性を返す。保存はしない。"""
        data = decode_image(image, self._settings.wardrobe_max_image_bytes)
        try:
            analysis = analyze_cloth_bytes(
                data, image.mime_type, settings=self._settings, client=self._client
            )
        except ClothIndexError as exc:
            cause = exc.__cause__
            logger.warning("服の写真の解析に失敗しました: %s", type(cause or exc).__name__)
            if cause is not None and is_quota_error(cause):
                raise WardrobeQuotaError(
                    "Gemini のクォータ(利用上限)を超えました。時間をおいて再解析してください。"
                ) from exc
            raise WardrobeError(f"写真の{exc}") from exc

        return AnalyzeResponse(
            items=[to_attributes(item) for item in analysis.items],
            summary=analysis.summary,
            model=self._settings.cloth_index_model,
        )

    def register(self, request: RegisterRequest) -> list[RegisteredCloth]:
        """確認・修正した服と写真を保存する。"""
        data = decode_image(request.image, self._settings.wardrobe_max_image_bytes)
        items = [to_cloth_item(attributes) for attributes in request.items]
        try:
            entry = self._store.add(
                data,
                request.image.mime_type,
                items,
                request.summary,
                self._settings.cloth_index_model,
            )
        except (WardrobeStoreError, OSError) as exc:
            logger.warning("服を保存できませんでした: %s", type(exc).__name__)
            raise WardrobeError(f"服を保存できませんでした: {exc}") from exc
        return to_registered(entry)

    def list_items(self) -> list[RegisteredCloth]:
        """登録済みの服を新しい順に返す。"""
        try:
            entries = self._store.list_entries()
        except (WardrobeStoreError, OSError) as exc:
            logger.warning("服の一覧を読み込めませんでした: %s", type(exc).__name__)
            raise WardrobeError(f"服の一覧を読み込めませんでした: {exc}") from exc
        return [item for entry in reversed(entries) for item in to_registered(entry)]

    def delete(self, item_id: str) -> None:
        """服 1 点を削除する。"""
        try:
            found = self._store.delete_item(item_id)
        except (WardrobeStoreError, OSError) as exc:
            logger.warning("服を削除できませんでした: %s", type(exc).__name__)
            raise WardrobeError(f"服を削除できませんでした: {exc}") from exc
        if not found:
            raise WardrobeNotFoundError("削除する服が見つかりませんでした。")

    def read_image(self, image: str) -> tuple[bytes, str]:
        """保存した写真を (バイト列, MIME タイプ) で返す。"""
        try:
            found = self._store.read_image(image)
        except (WardrobeStoreError, OSError) as exc:
            logger.warning("服の写真を読み込めませんでした: %s", type(exc).__name__)
            raise WardrobeError(f"写真を読み込めませんでした: {exc}") from exc
        if found is None:
            raise WardrobeNotFoundError("写真が見つかりませんでした。")
        return found


def get_wardrobe_service() -> WardrobeService:
    """FastAPI の Depends 用ファクトリ。テスト時は override して差し替える。"""
    return WardrobeService()
