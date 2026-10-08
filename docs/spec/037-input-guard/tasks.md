# 実装タスク: 利用者の入力のチェック

- 対応する設計: `./design.md`
- 進捗: 10 / 10

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 完了したら `- [ ]` を `- [x]` にする。

## タスク一覧

### バックエンド

- [x] **T-01: 不審な言い回しの検査(`input_guard.py`)**
  - 変更対象: `backend/app/services/input_guard.py`, `backend/tests/test_input_guard.py`
  - 完了条件: 当たる例・当たらない例(AC-4)・`wrap_user_input` のテストが通る
  - 関連 AC: AC-4, AC-6
- [x] **T-02: 入力の共通チェック(`GuardedRequest`)**
  - 変更対象: `backend/app/schemas/common.py` と ① ② ③ のリクエストの型, テスト
  - 完了条件: 制御文字・長すぎる文字列で 422、普通の入力と base64 の画像は通る
  - 関連 AC: AC-7(ID・ファイル名の形式の検査 = AC-8 は T-10 で取りやめ)
- [x] **T-03: ①②③ での検査と 400 への変換**
  - 変更対象: `backend/app/main.py`, `services/youtube.py`・`live.py`・`wardrobe_registry.py`, API のテスト
  - 完了条件: 不審な入力で 400 と理由、外部 API のフェイクが呼ばれない・保存されない
  - 関連 AC: AC-1, AC-2, AC-3, AC-6
- [x] **T-04: プロンプトの作り(区切りと指示)**
  - 変更対象: `services/live.py`・`outfit.py`, テスト(`grounding.py` は T-10 で元に戻した)
  - 完了条件: ライブ検索とコーデ提案のプロンプトにタグと指示が入るテストが通る。ruff / mypy が通る
  - 関連 AC: AC-5

### フロントエンド

- [x] **T-05: 400 の理由の表示の確認**
  - 変更対象: `frontend/test/`
  - 完了条件: ライブ検索の 400 の理由が ② のカードに出るテストが通る
  - 関連 AC: AC-1, AC-10

### 仕上げ

- [x] **T-06: ドキュメント更新**
  - 変更対象: `README.md`, spec 009・011 の design.md
  - 完了条件: README の記述(入力のチェック・将来 DB を使うときの決まり・誤検知の直し方)が実装と一致している
  - 関連 AC: AC-9

### 追加(2026-10-08)

- [x] **T-07: チャット API を閉じる**
  - 変更対象: `backend/app/api/router.py`, `routes/chat.py`, `tests/test_chat.py`, `tests/test_input_common.py`
  - 完了条件: `POST /api/v1/chat` が 404 になるテストが通る
  - 関連 AC: AC-11
- [x] **T-08: 規則の強化(前処理・言い換え・ひらがな・ローマ字・他の言語・項目の分割)**
  - 変更対象: `backend/app/services/input_guard.py`, `wardrobe_registry.py`, `tests/test_input_guard.py`, `tests/test_input_guard_api.py`
  - 完了条件: すり抜けた例がすべて断られ、普通の名前(AC-4 と追加の 16 例)は断られないテストが通る
  - 関連 AC: AC-12
- [x] **T-09: 語の組み合わせ(12 文字以内)**
  - 変更対象: `backend/app/services/input_guard.py`, `tests/test_input_guard.py`
  - 完了条件: 語の組み合わせで断る 7 例と、誤検知しやすい普通の入力 15 例(洗濯表示・ルール無用のデスマッチ・12 文字より離れた例など)のテストが通る
  - 関連 AC: AC-13
- [x] **T-10: 対象を利用者が文字を打ち込む 3 か所に絞る**
  - 変更対象: `schemas/chat.py`・`culture.py`・`venue.py`・`outfit.py`、`routes/wardrobe.py`、`services/grounding.py` を main に戻す。
    `AnalyzeRequest` を `BaseModel` に戻す。`schemas/common.py` から ID・ファイル名の形式を外す。
    `services/live.py` の指示を system instruction からプロンプトの本文へ移す。テスト・README・spec を合わせる
  - 完了条件: `GuardedRequest` を継承するのが `LookupRequest`・`LiveSearchRequest`・`RegisterRequest` だけで、pytest / ruff / mypy / flutter test が通る
  - 関連 AC: AC-5, AC-7(決定事項 8)
