# 設計: Agent ADK による Gemini 呼び出し

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-17

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | リクエストごとに使い捨てセッションを作り、`history` をイベントとして流し込む | 採用 | API 契約とフロントを変えずに済み、ステートレスなので複数インスタンスでも破綻しない |
| B | サーバ側でセッションを保持し、クライアントは `session_id` だけ送る | 却下 | ADK 本来の形だが API 契約とフロントの変更が必要。永続化方針が未決(未決事項 #1) |
| C | `google-genai` を直接呼ぶ(現状維持) | 却下 | ツール実行・マルチエージェントへの拡張時に作り直しになる |

## 2. 全体フロー

```
POST /api/v1/chat
  → AgentService.generate_reply(message, history)
      ├─ InMemorySessionService.create_session()        # リクエストごとに新規
      ├─ history を Event に変換して append_event()      # 文脈の再現
      └─ Runner.run_async(new_message=...)              # LlmAgent が Gemini を呼ぶ
           → Event ストリームから is_final_response() のテキストを取得
  → ChatResponse(reply, model)
```

## 3. API 設計

**変更なし。** `POST /api/v1/chat` のリクエスト / レスポンス形式は spec 000 のまま。
エラーも同じく 502(`AgentError` を変換)。

## 4. データモデル

変更なし(`ChatMessage` / `ChatRequest` / `ChatResponse`)。
ADK 内部では `google.genai.types.Content` / `google.adk.events.Event` に変換する。

| 本アプリの role | ADK Event の author |
| --- | --- |
| `user` | `user` |
| `model` | エージェント名(`chat_agent`) |

## 5. バックエンド設計

`app/services/agent.py`(`gemini.py` を置き換え):

| 要素 | 役割 |
| --- | --- |
| `AgentError` | ADK / Gemini 由来の失敗を表す業務例外。ルータが 502 に変換する |
| `_configure_google_env()` | `Settings` の値を `os.environ` に反映する。ADK は環境変数しか見ないため必須 |
| `build_agent()` | `LlmAgent` を生成(model / instruction / generate_content_config) |
| `get_runner()` | `Runner` + `InMemorySessionService` を `lru_cache` で共有 |
| `AgentService.generate_reply()` | セッション作成 → 履歴投入 → 実行 → 最終応答の抽出 |

設定の追加(`app/core/config.py`):

| 項目 | 既定値 | 用途 |
| --- | --- | --- |
| `adk_app_name` | `tx-hackathon-gc` | ADK のアプリ名(セッションの名前空間) |
| `agent_name` | `chat_agent` | エージェント名。Event の author になる |
| `agent_description` | (説明文) | マルチエージェント化したときの選択材料 |

`gemini_system_instruction` は `LlmAgent.instruction` として渡す
(`GenerateContentConfig.system_instruction` は使わない。ADK が instruction から組み立てるため)。

## 6. フロントエンド設計

変更なし。

## 7. エラーハンドリング / 非機能

- 設定不備(`GOOGLE_CLOUD_PROJECT` 未設定)は実行前に検出して `AgentError` を投げる。
- ADK / SDK の例外は全て `AgentError` に変換し、FastAPI 層で 502 にする。
- 最終応答が空、または応答イベントが無い場合も `AgentError`。
- `Runner` と `InMemorySessionService` はプロセス内で共有(毎回の生成コストを避ける)。

## 8. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend api | `/chat` | `dependency_overrides` で `AgentService` をフェイクに差し替え |
| backend unit | 履歴 → Event 変換、環境変数の反映 | 純粋関数として単体テスト(外部通信なし) |
