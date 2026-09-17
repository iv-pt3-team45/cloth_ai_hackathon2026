# 実装タスク: Agent ADK による Gemini 呼び出し

- 対応する設計: `./design.md`
- 進捗: 6 / 6

## タスク一覧

- [x] **T-01: 依存追加**
  - 変更対象: `backend/pyproject.toml`, `backend/uv.lock`
  - 完了条件: `uv add google-adk` が成功し、`uv sync --frozen --check` が差分なし
- [x] **T-02: 設定の追加と環境変数への反映**
  - 変更対象: `backend/app/core/config.py`
  - 完了条件: `adk_app_name` / `agent_name` が設定でき、`os.environ` に GCP 設定が反映される / 関連 AC: AC-3
- [x] **T-03: `agent.py` の実装(`gemini.py` を置き換え)**
  - 変更対象: `backend/app/services/agent.py`(削除: `gemini.py`)
  - 完了条件: `LlmAgent` + `Runner` 経由で応答テキストを取得できる / 関連 AC: AC-1, AC-2
- [x] **T-04: ルータの差し替え**
  - 変更対象: `backend/app/api/routes/chat.py`
  - 完了条件: API 契約を変えずに `AgentService` を DI する / 関連 AC: AC-1
- [x] **T-05: テスト更新 / 追加**
  - 変更対象: `backend/tests/`
  - 完了条件: `uv run python -m pytest` が外部通信なしで通る / 関連 AC: AC-4
- [x] **T-06: ドキュメント更新**
  - 変更対象: `README.md`, 本 spec
  - 完了条件: 技術スタック・アーキテクチャ図・ディレクトリ構成が ADK 構成に更新されている
