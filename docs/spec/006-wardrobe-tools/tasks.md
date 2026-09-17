# 実装タスク: 服インデックスをエージェントから参照する

- 対応する設計: `./design.md`
- 進捗: 4 / 4

## タスク一覧

- [x] **T-01: 設定の追加**
  - 変更対象: `backend/app/core/config.py`, `backend/.env.example`
  - 完了条件: `CLOTH_INDEX_PATH` で参照先を変更できる / 関連 AC: AC-5
- [x] **T-02: 参照サービスとツール**
  - 変更対象: `backend/app/services/wardrobe.py`
  - 完了条件: 一覧取得と検索ができ、インデックスが無くても例外を投げない / 関連 AC: AC-1, AC-2, AC-4
- [x] **T-03: エージェントへの登録と CLI オプション**
  - 変更対象: `backend/app/services/agent.py`, `backend/scripts/run_agent.py`, `backend/scripts/run_agent_loop.py`
  - 完了条件: 両 CLI でツールが使え、`--index` が効く / 関連 AC: AC-3, AC-5
- [x] **T-04: テストとドキュメント**
  - 変更対象: `backend/tests/test_wardrobe.py`, `README.md`
  - 完了条件: 外部通信なしでテストが通る / 関連 AC: AC-6
