"""コーデ提案(spec 011)のテスト用スタブ。Gemini は呼ばない。"""

import datetime as dt
from pathlib import Path
from typing import Any

from google.genai import types

from app.core.config import Settings
from app.schemas.culture import (
    BackgroundInfo,
    CultureResponse,
    FashionInfo,
    MvOutfit,
    OutfitItem,
    OutfitLook,
)
from app.schemas.live import LiveCandidate, LiveWeather
from app.services.cloth_index import ClothItem
from app.services.outfit import (
    OutfitService,
    VenueLookup,
    _OutfitOutput,
    _SuggestedItemOutput,
)
from app.services.venue import VenueFormat, VenueInfo
from app.services.wardrobe_store import LocalWardrobeStore
from tests.gemini_stub import Responder, parsed_response
from tests.gemini_stub import make_client as _make_client

JPEG_A = b"\xff\xd8\xff\xe0photo-a"
JPEG_B = b"\xff\xd8\xff\xe0photo-b"
MANNEQUIN = b"\xff\xd8\xff\xe0mannequin"
GENERATED = b"\x89PNG\r\n\x1a\ngenerated"


def make_settings(tmp_path: Path, **overrides: Any) -> Settings:
    mannequin = tmp_path / "assets" / "mannequin.jpeg"
    mannequin.parent.mkdir(parents=True, exist_ok=True)
    mannequin.write_bytes(MANNEQUIN)
    values: dict[str, Any] = {
        "cloth_index_path": str(tmp_path / "wardrobe" / "index.json"),
        "created_images_dir": str(tmp_path / "created"),
        "outfit_mannequin_path": str(mannequin),
        "outfit_model": "test-model",
        "image_model": "test-image",
        "outfit_timeout": 5,
        "media_generation_timeout": 5,
    }
    values.update(overrides)
    return Settings(**values)


def register_clothes(settings: Settings) -> dict[str, str]:
    """写真 A に T シャツとジーンズ、写真 B にスニーカーを登録し、種類 → id を返す。"""
    store = LocalWardrobeStore(settings.cloth_index_file)
    a = store.add(
        JPEG_A,
        "image/jpeg",
        [
            ClothItem(
                category="Tシャツ",
                material="綿",
                shape="半袖",
                colors=["白"],
                seasons=["夏"],
                warmth="薄手",
                occasions=["ライブ・フェス"],
            ),
            ClothItem(category="ジーンズ", material="デニム", shape="ストレート", colors=["青"]),
        ],
        "",
        "m",
    )
    b = store.add(
        JPEG_B, "image/jpeg", [ClothItem(category="スニーカー", material="", shape="")], "", "m"
    )
    return {item.category: item.id for item in [*a.items, *b.items]}


def make_video() -> Any:
    from tests.culture_stub import make_video as culture_video

    return culture_video()


def make_culture(identified: bool = True) -> CultureResponse:
    return CultureResponse(
        artist="YOASOBI" if identified else "",
        identified=identified,
        fashion=FashionInfo(
            styles=["ストリート"], colors=["黒"], items=["ベレー帽"], worldview="近未来"
        ),
        background=BackgroundInfo(summary="小説を音楽にするユニット", genres=["J-POP"]),
        mv_outfit=MvOutfit(
            status="ok",
            looks=[
                OutfitLook(
                    label="メインの衣装",
                    items=[OutfitItem(category="ワンピース", colors=["白"], style="ガーリー")],
                )
            ],
        ),
        model="m",
    )


def make_live(weather: LiveWeather | None = None) -> LiveCandidate:
    return LiveCandidate(
        index=1,
        live_name="ARENA TOUR",
        venue="さいたまスーパーアリーナ",
        location="埼玉県さいたま市",
        date=dt.date(2023, 6, 3),
        weather=weather or LiveWeather(kind="actual", summary="晴れ", high_c=28.5, low_c=18.0),
    )


def suggestion(*ids: str) -> _OutfitOutput:
    return _OutfitOutput(
        title="晴れの日のライブコーデ",
        summary="動きやすいカジュアル",
        points=["晴れで暑いため薄手", "情報なし"],
        items=[
            _SuggestedItemOutput(id=i, role="トップス", reason=f"{i} を選んだ理由") for i in ids
        ],
    )


def image_response(data: bytes = GENERATED, mime_type: str = "image/png") -> Any:
    return types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(
                    role="model",
                    parts=[
                        types.Part(text="できました"),
                        types.Part(inline_data=types.Blob(data=data, mime_type=mime_type)),
                    ],
                )
            )
        ]
    )


def responder(output: _OutfitOutput | None = None, image: Any = None) -> Responder:
    """提案の呼び出し(response_schema あり)と画像の呼び出し(response_modalities あり)に応える。"""

    def respond(call: dict[str, Any]) -> Any:
        if call["config"].response_modalities:
            return image if image is not None else image_response()
        return parsed_response(output)

    return respond


def unknown_venue(venue_name: str, **_: Any) -> VenueInfo:
    """既定の会場の形態の取得。外部通信はせず、形態不明を返す。"""
    return VenueInfo(venue_name=venue_name, format=VenueFormat.UNKNOWN)


def make_service(
    settings: Settings, respond: Responder, venue_lookup: VenueLookup = unknown_venue
) -> tuple[OutfitService, Any]:
    client = _make_client(respond)
    service = OutfitService(
        settings=settings,
        store=LocalWardrobeStore(settings.cloth_index_file),
        client=client,
        venue_lookup=venue_lookup,
    )
    return service, client
