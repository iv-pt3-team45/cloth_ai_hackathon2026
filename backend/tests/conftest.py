import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.schemas.chat import Attachment, ChatMessage
from app.services.agent import AgentService, get_agent_service


class FakeAgentService(AgentService):
    """ADK / 外部 API を呼ばないテスト用スタブ。"""

    async def generate_reply(
        self,
        message: str,
        history: list[ChatMessage],
        attachments: list[Attachment] | None = None,
    ) -> str:
        suffix = f" (+{len(attachments)} files)" if attachments else ""
        return f"echo: {message}{suffix}"


@pytest.fixture
def client() -> TestClient:
    app = create_app()
    app.dependency_overrides[get_agent_service] = FakeAgentService
    return TestClient(app)
