# 実装タスク: エージェントループ

- 対応する設計: `./design.md`
- 進捗: 5 / 5

## タスク一覧

- [x] **T-01: 設定の追加**
  - 変更対象: `backend/app/core/config.py`, `backend/.env.example`
  - 完了条件: `VERIFIER_MODEL` / `LOOP_MAX_ITERATIONS` が設定できる
- [x] **T-02: 検証サービス**
  - 変更対象: `backend/app/services/verification.py`
  - 完了条件: 画像を含めて構造化 JSON で判定できる / 関連 AC: AC-5
- [x] **T-03: ループ本体**
  - 変更対象: `backend/app/services/agent_loop.py`
  - 完了条件: 満足で終了 / 上限で終了 / 指摘の引き継ぎ / 関連 AC: AC-2, AC-3, AC-4
- [x] **T-04: CLI**
  - 変更対象: `backend/scripts/run_agent_loop.py`
  - 完了条件: 経過が表示され、終了コードが判定結果に対応する / 関連 AC: AC-1
- [x] **T-05: テストとドキュメント**
  - 変更対象: `backend/tests/test_agent_loop.py`, `README.md`
  - 完了条件: 外部通信なしでループの停止条件を検証できる / 関連 AC: AC-6
