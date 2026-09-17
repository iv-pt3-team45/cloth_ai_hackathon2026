"""ADK 連携部分の単体テスト(外部通信は行わない)。"""

import pytest
from google.adk.events import Event
from google.genai import types

from app.core.config import Settings
from app.schemas.chat import ChatMessage
from app.services.agent import AgentError, build_agent, extract_reply, get_runner, to_event


def test_to_event_maps_user_role() -> None:
    event = to_event(ChatMessage(role="user", content="こんにちは"), "chat_agent")
    assert event.author == "user"
    assert event.content is not None
    assert event.content.parts is not None
    assert event.content.parts[0].text == "こんにちは"


def test_to_event_maps_model_role_to_agent_name() -> None:
    event = to_event(ChatMessage(role="model", content="はい"), "chat_agent")
    assert event.author == "chat_agent"


def test_extract_reply_returns_text_of_final_response() -> None:
    event = Event(
        author="chat_agent",
        content=types.Content(role="model", parts=[types.Part.from_text(text="応答")]),
    )
    assert extract_reply(event) == "応答"


def test_extract_reply_ignores_partial_event() -> None:
    event = Event(
        author="chat_agent",
        partial=True,
        content=types.Content(role="model", parts=[types.Part.from_text(text="途中")]),
    )
    assert extract_reply(event) is None


def test_build_agent_uses_settings() -> None:
    settings = Settings(
        agent_name="test_agent",
        gemini_model="gemini-2.5-flash",
        gemini_system_instruction="テスト用の指示",
    )
    agent = build_agent(settings)
    assert agent.name == "test_agent"
    assert agent.model == "gemini-2.5-flash"
    # instruction には設定値に加えてツール利用のガイドラインが付く
    assert agent.instruction.startswith("テスト用の指示")
    assert "generate_image" in agent.instruction
    assert agent.generate_content_config is not None
    assert agent.generate_content_config.temperature == settings.gemini_temperature


def test_export_google_env_sets_vertexai_flag(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("GOOGLE_GENAI_USE_VERTEXAI", raising=False)
    monkeypatch.delenv("GOOGLE_CLOUD_PROJECT", raising=False)

    Settings(google_genai_use_vertexai=True, google_cloud_project="demo").export_google_env()

    import os

    assert os.environ["GOOGLE_GENAI_USE_VERTEXAI"] == "TRUE"
    assert os.environ["GOOGLE_CLOUD_PROJECT"] == "demo"


def test_get_runner_requires_project(monkeypatch: pytest.MonkeyPatch) -> None:
    """プロジェクト未設定なら、外部を呼ぶ前に設定不備として失敗する。"""
    monkeypatch.setattr(
        "app.services.agent.get_settings", lambda: Settings(google_cloud_project="")
    )
    get_runner.cache_clear()

    with pytest.raises(AgentError, match="GOOGLE_CLOUD_PROJECT"):
        get_runner()

    get_runner.cache_clear()
