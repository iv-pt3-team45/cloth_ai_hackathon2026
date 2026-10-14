"""コーデ提案サービスのテスト(Gemini はフェイクのクライアントで差し替える)。"""

import asyncio
import base64
import time
from pathlib import Path
from typing import Any

import pytest
from google.genai import errors, types

from app.schemas.live import LiveWeather
from app.services.input_guard import UNTRUSTED_INPUT_RULE
from app.services.outfit import (
    _SUGGEST_INSTRUCTION,
    OutfitError,
    OutfitInputError,
    OutfitQuotaError,
    OutfitTimeoutError,
    build_suggest_prompt,
    load_owned,
)
from app.services.venue import VenueFormat, VenueInfo
from app.services.wardrobe_store import LocalWardrobeStore
from tests.gemini_stub import calls_of
from tests.outfit_stub import (
    GENERATED,
    JPEG_A,
    JPEG_B,
    MANNEQUIN,
    make_culture,
    make_live,
    make_service,
    make_settings,
    make_video,
    register_clothes,
    responder,
    suggestion,
)


def api_error(code: int, status: str = "INTERNAL") -> errors.APIError:
    return errors.ClientError(code, {"error": {"code": code, "message": "x", "status": status}})


# --- 提案のプロンプト ------------------------------------------------------


def test_prompt_includes_all_context(tmp_path: Path) -> None:
    """AC-9: 手持ちの服・MV・アーティスト・カルチャー・ライブ・天気が入る。"""
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)
    owned = load_owned(LocalWardrobeStore(settings.cloth_index_file))

    prompt = build_suggest_prompt(owned, make_video(), make_culture(), make_live())

    assert f"id={ids['Tシャツ']}: Tシャツ / 色: 白 / 素材: 綿 / 形: 半袖" in prompt
    assert "季節: 夏 / 暖かさ: 薄手 / 場面: ライブ・フェス" in prompt
    assert f"id={ids['スニーカー']}: スニーカー" in prompt
    assert "- 曲名: アイドル" in prompt
    assert "- ファッションのスタイル: ストリート" in prompt
    assert "- この MV の衣装「メインの衣装」: ワンピース(白 / ガーリー)" in prompt
    assert "- 音楽ジャンル: J-POP" in prompt
    assert "- 会場: さいたまスーパーアリーナ(埼玉県さいたま市)" in prompt
    assert "- 日付: 2023-06-03" in prompt
    assert "- 当日の天気: 晴れ / 最高 28.5℃ / 最低 18℃(実績)" in prompt


def test_prompt_wraps_owned_clothes_as_user_data(tmp_path: Path) -> None:
    """spec 037 AC-5: 利用者が修正できる服の属性は区切り、指示に従わないよう指示する。"""
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)
    owned = load_owned(LocalWardrobeStore(settings.cloth_index_file))

    prompt = build_suggest_prompt(owned, make_video(), make_culture(), make_live())

    clothes = prompt.split("<user_data>", 1)[1].split("</user_data>", 1)[0]
    assert f"- id={ids['Tシャツ']}: Tシャツ" in clothes
    assert "# MV" not in clothes
    assert UNTRUSTED_INPUT_RULE in _SUGGEST_INSTRUCTION


def test_prompt_without_culture_and_weather(tmp_path: Path) -> None:
    settings = make_settings(tmp_path)
    register_clothes(settings)
    owned = load_owned(LocalWardrobeStore(settings.cloth_index_file))

    prompt = build_suggest_prompt(owned, make_video(), None, make_live(LiveWeather(kind="not_yet")))

    assert "- 取得できていない(MV の情報から考える)" in prompt
    assert "予報はまだ出ていない" in prompt


def test_prompt_includes_venue_format(tmp_path: Path) -> None:
    """F14 で調べた会場の形態が「行くライブ」に入る。"""
    settings = make_settings(tmp_path)
    register_clothes(settings)
    owned = load_owned(LocalWardrobeStore(settings.cloth_index_file))

    standing = build_suggest_prompt(owned, make_video(), None, make_live(), VenueFormat.STANDING)
    seated = build_suggest_prompt(owned, make_video(), None, make_live(), VenueFormat.SEATED)

    mixed = build_suggest_prompt(owned, make_video(), None, make_live(), VenueFormat.MIXED)

    assert "- 会場の形態: スタンディング" in standing
    assert "- 会場の形態: 着席" in seated
    assert "- 会場の形態: 混在(" in mixed


def test_prompt_omits_unknown_venue_format(tmp_path: Path) -> None:
    """形態が分からないときは行ごと足さない。"""
    settings = make_settings(tmp_path)
    register_clothes(settings)
    owned = load_owned(LocalWardrobeStore(settings.cloth_index_file))

    for venue_format in (None, VenueFormat.UNKNOWN):
        prompt = build_suggest_prompt(owned, make_video(), None, make_live(), venue_format)
        assert "会場の形態" not in prompt


# --- 提案 ------------------------------------------------------------------


async def test_suggest_uses_venue_format(tmp_path: Path) -> None:
    """ライブの会場名・所在地・ライブ名・公演日を F14 に渡し、形態をプロンプトに足す。"""
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)
    received: dict[str, Any] = {}

    def standing(venue_name: str, **kwargs: Any) -> VenueInfo:
        received.update(venue_name=venue_name, **kwargs)
        return VenueInfo(venue_name=venue_name, format=VenueFormat.STANDING)

    service, client = make_service(settings, responder(suggestion(ids["Tシャツ"])), standing)

    await service.suggest(make_video(), None, make_live())

    assert received["venue_name"] == "さいたまスーパーアリーナ"
    assert received["location"] == "埼玉県さいたま市"
    assert received["live_name"] == "ARENA TOUR"
    assert received["live_date"] == "2023-06-03"
    assert "- 会場の形態: スタンディング" in calls_of(client)[0]["contents"]


async def test_suggest_uses_given_venue_format_without_lookup(tmp_path: Path) -> None:
    """画面が調べた形態を送ってきたら、それを使い、もう一度は調べない。"""
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)
    called: list[str] = []

    def record(venue_name: str, **_: Any) -> VenueInfo:
        called.append(venue_name)
        return VenueInfo(venue_name=venue_name, format=VenueFormat.STANDING)

    service, client = make_service(settings, responder(suggestion(ids["Tシャツ"])), record)

    await service.suggest(make_video(), None, make_live(), VenueFormat.SEATED)

    assert called == []
    assert "- 会場の形態: 着席" in calls_of(client)[0]["contents"]


async def test_suggest_does_not_lookup_again_when_given_unknown(tmp_path: Path) -> None:
    """unknown が送られてきた(画面で調べたが分からなかった)ときも、もう一度は調べない。"""
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)
    called: list[str] = []

    def record(venue_name: str, **_: Any) -> VenueInfo:
        called.append(venue_name)
        return VenueInfo(venue_name=venue_name, format=VenueFormat.STANDING)

    service, client = make_service(settings, responder(suggestion(ids["Tシャツ"])), record)

    await service.suggest(make_video(), None, make_live(), VenueFormat.UNKNOWN)

    assert called == []
    assert "会場の形態" not in calls_of(client)[0]["contents"]


async def test_suggest_continues_when_venue_lookup_fails(tmp_path: Path) -> None:
    """F14 が失敗しても、形態なしで提案する。"""
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)

    def failed(venue_name: str, **_: Any) -> VenueInfo:
        return VenueInfo(venue_name=venue_name, status="error", message="APIエラー")

    service, client = make_service(settings, responder(suggestion(ids["Tシャツ"])), failed)

    result = await service.suggest(make_video(), None, make_live())

    assert [item.category for item in result.items] == ["Tシャツ"]
    assert "会場の形態" not in calls_of(client)[0]["contents"]


async def test_suggest_continues_when_venue_lookup_times_out(tmp_path: Path) -> None:
    """F14 が時間切れになっても、形態なしで提案する。"""
    settings = make_settings(tmp_path, venue_info_timeout=0.05)
    ids = register_clothes(settings)

    def slow(venue_name: str, **_: Any) -> VenueInfo:
        time.sleep(0.3)
        return VenueInfo(venue_name=venue_name, format=VenueFormat.STANDING)

    service, client = make_service(settings, responder(suggestion(ids["Tシャツ"])), slow)

    result = await service.suggest(make_video(), None, make_live())

    assert [item.category for item in result.items] == ["Tシャツ"]
    assert "会場の形態" not in calls_of(client)[0]["contents"]


async def test_suggest_skips_venue_lookup_without_venue(tmp_path: Path) -> None:
    """会場名が無ければ F14 を呼ばない。"""
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)
    called: list[str] = []

    def record(venue_name: str, **_: Any) -> VenueInfo:
        called.append(venue_name)
        return VenueInfo(venue_name=venue_name)

    service, _ = make_service(settings, responder(suggestion(ids["Tシャツ"])), record)
    live = make_live().model_copy(update={"venue": ""})

    await service.suggest(make_video(), None, live)

    assert called == []


async def test_suggest_uses_only_owned_clothes(tmp_path: Path) -> None:
    """AC-9 / AC-10: 手持ちに無い服と重複は除き、その数を返す。"""
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)
    output = suggestion(ids["Tシャツ"], "not-owned", ids["ジーンズ"], ids["Tシャツ"])
    service, client = make_service(settings, responder(output))

    result = await service.suggest(make_video(), make_culture(), make_live())

    assert [item.category for item in result.items] == ["Tシャツ", "ジーンズ"]
    assert result.excluded_count == 1
    first = result.items[0]
    assert first.role == "トップス"
    assert first.reason == f"{ids['Tシャツ']} を選んだ理由"
    assert first.image.startswith("cloth-")
    assert first.seasons == ["夏"]
    assert result.title == "晴れの日のライブコーデ"
    assert result.points == ["晴れで暑いため薄手"]
    assert result.model == "test-model"
    config = calls_of(client)[0]["config"]
    assert config.response_schema is not None
    assert config.automatic_function_calling.disable is True


async def test_suggest_requires_owned_clothes(tmp_path: Path) -> None:
    """手持ちの服が無ければ Gemini を呼ばない。"""
    service, client = make_service(make_settings(tmp_path), responder(suggestion()))

    with pytest.raises(OutfitInputError, match="登録されていません"):
        await service.suggest(make_video(), make_culture(), make_live())
    assert calls_of(client) == []


async def test_suggest_fails_when_no_owned_item_is_used(tmp_path: Path) -> None:
    """AC-10: 手持ちの服を 1 点も使えなかったら提案にしない。"""
    settings = make_settings(tmp_path)
    register_clothes(settings)
    service, _ = make_service(settings, responder(suggestion("not-owned")))

    with pytest.raises(OutfitError, match="作れませんでした"):
        await service.suggest(make_video(), make_culture(), make_live())


async def test_suggest_fails_when_unreadable(tmp_path: Path) -> None:
    settings = make_settings(tmp_path)
    register_clothes(settings)
    service, _ = make_service(settings, responder(None))

    with pytest.raises(OutfitError, match="解釈"):
        await service.suggest(make_video(), None, make_live())


async def test_suggest_errors(tmp_path: Path) -> None:
    """AC-13: クォータ超過は区別する。"""
    settings = make_settings(tmp_path)
    register_clothes(settings)

    def quota(call: dict[str, Any]) -> Any:
        raise api_error(429, "RESOURCE_EXHAUSTED")

    def broken(call: dict[str, Any]) -> Any:
        raise api_error(500)

    with pytest.raises(OutfitQuotaError):
        await make_service(settings, quota)[0].suggest(make_video(), None, make_live())
    with pytest.raises(OutfitError, match="コーデの提案に失敗しました") as info:
        await make_service(settings, broken)[0].suggest(make_video(), None, make_live())
    assert not isinstance(info.value, OutfitQuotaError)


async def test_suggest_times_out(tmp_path: Path) -> None:
    settings = make_settings(tmp_path, outfit_timeout=0.05)
    register_clothes(settings)

    async def slow(call: dict[str, Any]) -> Any:
        await asyncio.sleep(10)

    with pytest.raises(OutfitTimeoutError, match="秒以内"):
        await make_service(settings, slow)[0].suggest(make_video(), None, make_live())


# --- 画像の生成 --------------------------------------------------------------


async def test_generate_image_passes_mannequin_and_photos(tmp_path: Path) -> None:
    """AC-11: マネキン画像と、服の写真そのもの(同じ写真は 1 回)を渡し、生成画像を保存して返す。"""
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)
    service, client = make_service(settings, responder())

    result = await service.generate_image([ids["Tシャツ"], ids["ジーンズ"], ids["スニーカー"]])

    call = calls_of(client)[0]
    assert call["model"] == "test-image"
    # コーデ画像ではテキストの出力を許さない
    assert call["config"].response_modalities == ["IMAGE"]
    parts: list[types.Part] = call["contents"][0].parts
    images = [p.inline_data.data for p in parts if p.inline_data]
    # 1 枚目がマネキン。写真 A(T シャツとジーンズ)は 1 回だけ
    assert images == [MANNEQUIN, JPEG_A, JPEG_B]
    instruction = parts[-1].text
    assert "- 画像 2 の写真から: Tシャツ(白)、ジーンズ(青)" in instruction
    assert "- 画像 3 の写真から: スニーカー" in instruction
    # コーデ名は入れない(ロゴ入りの服と重なると画像が返らなかったため)
    assert "コーデ名" not in instruction
    assert "写真に無い服や小物を足さないこと" in instruction
    # マネキンの黒のインナーは提案の服で覆う
    assert "黒のインナーは、着せた服で覆って見えないようにすること" in instruction
    # 生成画像は created_images/ に保存し、base64 でも返す
    assert base64.b64decode(result.data) == GENERATED
    assert result.mime_type == "image/png"
    assert (settings.created_images_path / result.file_name).read_bytes() == GENERATED
    assert result.file_name.startswith("outfit-")


async def test_generate_image_rejects_unknown_items(tmp_path: Path) -> None:
    """AC-10: 手持ちに無い服は画像の生成に使わない。"""
    settings = make_settings(tmp_path)
    register_clothes(settings)
    service, client = make_service(settings, responder())

    with pytest.raises(OutfitInputError):
        await service.generate_image(["not-owned"])
    assert calls_of(client) == []


async def test_generate_image_requires_mannequin(tmp_path: Path) -> None:
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)
    settings.outfit_mannequin_file.unlink()
    service, client = make_service(settings, responder())

    with pytest.raises(OutfitError, match="マネキン画像が見つかりません"):
        await service.generate_image([ids["Tシャツ"]])
    assert calls_of(client) == []


async def test_generate_image_fails_without_image(tmp_path: Path) -> None:
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)
    text_only = types.GenerateContentResponse(
        candidates=[
            types.Candidate(content=types.Content(role="model", parts=[types.Part(text="x")]))
        ]
    )
    service, _ = make_service(settings, responder(image=text_only))

    with pytest.raises(OutfitError, match="画像を返しませんでした"):
        await service.generate_image([ids["Tシャツ"]])


async def test_generate_image_errors(tmp_path: Path) -> None:
    """AC-13"""
    settings = make_settings(tmp_path)
    ids = register_clothes(settings)

    def quota(call: dict[str, Any]) -> Any:
        raise api_error(429, "RESOURCE_EXHAUSTED")

    with pytest.raises(OutfitQuotaError):
        await make_service(settings, quota)[0].generate_image([ids["Tシャツ"]])
