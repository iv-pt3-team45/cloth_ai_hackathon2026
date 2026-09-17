# 実装タスク: 服画像のインデックス作成

- 対応する設計: `./design.md`
- 進捗: 4 / 4

## タスク一覧

- [x] **T-01: スキーマと解析処理**
  - 変更対象: `backend/app/services/cloth_index.py`, `backend/app/core/config.py`
  - 完了条件: 画像 1 枚から素材・形・色・系統を構造化出力で取得できる / 関連 AC: AC-1, AC-3
- [x] **T-02: 保存処理**
  - 変更対象: `backend/app/services/cloth_index.py`
  - 完了条件: `index.json` 1 ファイルに全件をまとめて書き出せる / 関連 AC: AC-2
- [x] **T-03: CLI**
  - 変更対象: `backend/scripts/build_cloth_index.py`
  - 完了条件: 入出力ディレクトリを指定でき、スキップと `--force` が効く / 関連 AC: AC-4, AC-5
- [x] **T-04: テストとドキュメント**
  - 変更対象: `backend/tests/test_cloth_index.py`, `README.md`
  - 完了条件: 外部通信なしでテストが通り、README に使い方がある / 関連 AC: AC-6
