# 実装タスク: 画像 / 動画生成ツール

- 対応する設計: `./design.md`
- 進捗: 6 / 6

## タスク一覧

- [x] **T-01: 設定の追加**
  - 変更対象: `backend/app/core/config.py`, `backend/.env.example`
  - 完了条件: モデル名と保存先を設定で変更でき、絶対パスに解決される
- [x] **T-02: メディア生成サービスの実装**
  - 変更対象: `backend/app/services/media.py`
  - 完了条件: 画像は `generate_content`、動画は `interactions.create` で生成し保存できる / 関連 AC: AC-1, AC-3
- [x] **T-03: エージェントへのツール登録**
  - 変更対象: `backend/app/services/agent.py`
  - 完了条件: `LlmAgent(tools=[...])` に登録され、依頼時に呼ばれる / 関連 AC: AC-1, AC-4
- [x] **T-04: 異常系の扱い**
  - 変更対象: `backend/app/services/media.py`
  - 完了条件: 失敗時に例外を投げず `status: error` を返す / 関連 AC: AC-5
- [x] **T-05: テスト**
  - 変更対象: `backend/tests/test_media.py`
  - 完了条件: 外部通信なしで通る / 関連 AC: AC-6
- [x] **T-06: ドキュメントと .gitignore**
  - 変更対象: `README.md`, `.gitignore`, 本 spec
  - 完了条件: 生成物がコミット対象外で、README に使い方が載っている
