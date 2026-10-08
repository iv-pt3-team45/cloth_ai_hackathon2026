"""チャット API は閉じている(spec 037)。エージェント自体のテストは test_agent.py。"""

from fastapi.testclient import TestClient


def test_chat_api_is_closed(client: TestClient) -> None:
    res = client.post("/api/v1/chat", json={"message": "こんにちは", "history": []})

    assert res.status_code == 404
