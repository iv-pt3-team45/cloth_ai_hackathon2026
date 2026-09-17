# 実装タスク: エージェント単体実行 CLI とマルチモーダル入力

- 対応する設計: `./design.md`
- 進捗: 6 / 6

## タスク一覧

- [x] **T-01: `Attachment` スキーマの追加**
  - 変更対象: `backend/app/schemas/chat.py`
  - 完了条件: `data` / `uri` の排他検証が効く / 関連 AC: AC-5
- [x] **T-02: 添付ヘルパーの実装**
  - 変更対象: `backend/app/services/attachments.py`
  - 完了条件: ローカルファイルを base64 化でき、`gs://` は URI のまま扱える / 関連 AC: AC-4, AC-6
- [x] **T-03: `AgentService` のマルチモーダル対応**
  - 変更対象: `backend/app/services/agent.py`
  - 完了条件: `to_parts()` がテキスト + 添付を Part に変換する / 関連 AC: AC-2
- [x] **T-04: ルータの対応**
  - 変更対象: `backend/app/api/routes/chat.py`
  - 完了条件: `attachments` を渡す。無い場合は従来どおり動く / 関連 AC: AC-5
- [x] **T-05: CLI の実装**
  - 変更対象: `backend/scripts/run_agent.py`
  - 完了条件: 対話 / 単発の双方が動く / 関連 AC: AC-1, AC-3
- [x] **T-06: テストとドキュメント**
  - 変更対象: `backend/tests/`, `README.md`, 本 spec
  - 完了条件: `uv run python -m pytest` が通り、README に CLI の使い方が載っている
