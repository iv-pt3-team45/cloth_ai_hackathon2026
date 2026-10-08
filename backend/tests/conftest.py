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


@pytest.fixture(autouse=True)
def _local_wardrobe_storage(monkeypatch: pytest.MonkeyPatch) -> None:
    """backend/.env で WARDROBE_STORAGE=gcs にしていても、テストでは Cloud Storage を呼ばない。

    環境変数は .env より優先される。Cloud Storage を使うテストは Settings の引数で明示する。
    """
    monkeypatch.setenv("WARDROBE_STORAGE", "local")


@pytest.fixture
def client() -> TestClient:
    app = create_app()
    app.dependency_overrides[get_agent_service] = FakeAgentService
    return TestClient(app)
