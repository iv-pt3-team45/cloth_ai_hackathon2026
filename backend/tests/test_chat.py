from fastapi.testclient import TestClient


def test_chat_returns_reply(client: TestClient) -> None:
    res = client.post("/api/v1/chat", json={"message": "こんにちは", "history": []})
    assert res.status_code == 200
    body = res.json()
    assert body["reply"] == "echo: こんにちは"
    assert body["model"]


def test_chat_rejects_empty_message(client: TestClient) -> None:
    res = client.post("/api/v1/chat", json={"message": "", "history": []})
    assert res.status_code == 422


def test_chat_accepts_attachments(client: TestClient) -> None:
    res = client.post(
        "/api/v1/chat",
        json={
            "message": "この画像を説明して",
            "history": [],
            "attachments": [{"mime_type": "image/png", "data": "aW1n"}],
        },
    )
    assert res.status_code == 200
    assert res.json()["reply"] == "echo: この画像を説明して (+1 files)"


def test_chat_rejects_attachment_with_both_sources(client: TestClient) -> None:
    res = client.post(
        "/api/v1/chat",
        json={
            "message": "説明して",
            "attachments": [{"mime_type": "image/png", "data": "aW1n", "uri": "gs://b/o.png"}],
        },
    )
    assert res.status_code == 422
