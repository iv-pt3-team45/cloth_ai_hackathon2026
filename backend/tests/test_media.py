"""メディア生成ツールのテスト(外部 API は呼ばない)。"""

from pathlib import Path

import pytest

from app.core.config import Settings
from app.services import media
from app.services.agent import build_agent
from app.services.media import (
    MediaGenerationError,
    build_file_name,
    generate_image,
    generate_video,
    save_media,
)


def test_build_file_name_uses_mime_extension() -> None:
    name = build_file_name("image", "image/jpeg", ".png")
    assert name.startswith("image-")
    assert name.endswith(".jpg")


def test_build_file_name_falls_back_for_unknown_mime() -> None:
    assert build_file_name("video", "video/unknown", ".mp4").endswith(".mp4")


def test_build_file_name_is_unique() -> None:
    names = {build_file_name("image", "image/png", ".png") for _ in range(20)}
    assert len(names) == 20


def test_save_media_creates_directory(tmp_path: Path) -> None:
    directory = tmp_path / "created_images"

    path = save_media(b"binary", directory, "image-test.png")

    assert path.exists()
    assert path.read_bytes() == b"binary"
    assert path.parent == directory


def test_save_media_rejects_empty_data(tmp_path: Path) -> None:
    with pytest.raises(MediaGenerationError, match="空"):
        save_media(b"", tmp_path, "empty.png")


def test_generate_image_returns_error_dict_on_failure(monkeypatch: pytest.MonkeyPatch) -> None:
    """ツールは例外を投げずにエラーを返す(エージェントを止めないため)。"""

    def boom(prompt: str, settings: Settings) -> dict[str, object]:
        raise MediaGenerationError("クォータ超過")

    monkeypatch.setattr(media, "_generate_image", boom)

    result = generate_image("青空")

    assert result["status"] == "error"
    assert "クォータ超過" in str(result["message"])


def test_generate_video_returns_error_dict_on_failure(monkeypatch: pytest.MonkeyPatch) -> None:
    def boom(prompt: str, settings: Settings) -> dict[str, object]:
        raise MediaGenerationError("失敗")

    monkeypatch.setattr(media, "_generate_video", boom)

    assert generate_video("波の動画")["status"] == "error"


def test_created_paths_are_absolute() -> None:
    settings = Settings()
    assert settings.created_images_path.is_absolute()
    assert settings.created_images_path.name == "created_images"
    assert settings.created_videos_path.name == "created_videos"


def test_agent_has_media_tools() -> None:
    agent = build_agent(Settings())
    names = {getattr(tool, "__name__", getattr(tool, "name", "")) for tool in agent.tools}
    assert {"generate_image", "generate_video"} <= names
