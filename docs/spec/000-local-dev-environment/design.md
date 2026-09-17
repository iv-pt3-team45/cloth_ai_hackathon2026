# 設計: ローカル開発環境の整備

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-16

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | compose でフロント/バック両方をコンテナ起動、ネイティブ起動も併用可 | 採用 | 「全部入りで起動」と「高速な単体開発」を両立できる |
| B | 全てネイティブ起動、compose 無し | 却下 | 環境差異が出やすく、要件(同時起動)を満たさない |
| C | フロントも本番同様に nginx 配信のみ | 却下 | ホットリロードが効かず開発速度が落ちる(prod ステージとして残す) |

## 2. 全体フロー

```
Flutter Web (localhost:8080)
  └─ ApiClient (http)  ──► FastAPI (localhost:8000)
                              └─ GeminiService (google-genai)
                                   └─ Vertex AI / Gemini
```

## 3. API 設計

### `GET /api/v1/health`
レスポンス: `{"status":"ok","app":"...","environment":"local","version":"0.1.0"}`

### `POST /api/v1/chat`
リクエスト: `{"message":"...","history":[{"role":"user","content":"..."}]}`
レスポンス: `{"reply":"...","model":"gemini-2.5-flash"}`

| ステータス | 条件 |
| --- | --- |
| 422 | message が空 / 8000 文字超 |
| 502 | Gemini 呼び出し失敗(`GeminiError`) |

## 4. データモデル

- backend: `app/schemas/chat.py` の `ChatMessage` / `ChatRequest` / `ChatResponse`
- frontend: `lib/features/chat/chat_models.dart` の `ChatMessage`
- 永続化は行わない(履歴は画面のメモリ上のみ)。

## 5. フロントエンド設計

- `lib/core/app_config.dart`: `--dart-define=API_BASE_URL` で接続先を切り替え。
- `lib/core/api_client.dart`: JSON の送受信と `ApiException` への変換。
- `lib/features/chat/`: モデル / リポジトリ / 画面。テストではリポジトリをフェイクに差し替える。

## 6. バックエンド設計

- `app/main.py`: `create_app()` で CORS とルータを組み立て、`lifespan` でロギング初期化。
- `app/api/router.py`: 機能ごとのルータをここに集約する。
- `app/core/config.py`: `pydantic-settings` による設定。`get_settings()` を DI する。
- ~~`app/services/gemini.py`: `google-genai` の `Client` を `lru_cache` で共有し、SDK 例外を `GeminiError` に変換。~~
  → **spec 001 で `app/services/agent.py`(ADK 経由)に置き換え済み。**

## 7. Gemini プロンプト設計

> 呼び出し方は spec 001(Agent ADK)で置き換えられている。以下は当初設計。

- モデル: `gemini-2.5-flash`(`GEMINI_MODEL` で変更可)
- `system_instruction` は設定値。履歴は `types.Content` のリストに変換して渡す。
- 空応答は `GeminiError` として 502 を返す。

## 8. エラーハンドリング / 非機能

- 外部 API 例外は全てサービス層で捕捉し、HTTP 層で 502 に変換する。
- ログはローカルで人間可読、それ以外は JSON 構造化。
- 資格情報は `.env` と `infra/secrets/` に置き、どちらも Git 管理外。

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend api | `/health`, `/chat` | `TestClient` + `dependency_overrides` |
| frontend | チャット画面 | `flutter test` + `FakeChatRepository` |
| 結合 | 全体起動 | `docker compose up` で手動確認 |
