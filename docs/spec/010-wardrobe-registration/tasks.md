# 実装タスク: 手持ちの服の写真を登録する

- 対応する設計: `./design.md`
- 進捗: 8 / 9

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 完了したら `- [ ]` を `- [x]` にする。

## タスク一覧

### バックエンド

- [x] **T-01: 属性の追加と画像データでの解析**
  - 変更対象: `backend/app/services/cloth_index.py`, `backend/app/schemas/wardrobe.py`, `backend/app/services/wardrobe.py`, `backend/tests/test_cloth_index.py`
  - 完了条件: 3 項目が追加され、選択肢の外の値が捨てられ、既存の `index.json` も読めるテストが通る。005 / 006 / 008 の既存テストが通る
  - 関連 AC: AC-2, AC-3, AC-4
- [x] **T-02: 保存(ローカルの WardrobeStore)**
  - 変更対象: `backend/app/services/wardrobe_store.py`, `backend/app/core/config.py`, `backend/.env.example`, `.gitignore`, `backend/tests/test_wardrobe_store.py`
  - 完了条件: 追加・一覧・削除・写真の削除・既存形式の読み込み・005 / 006 の読み込みとの互換のテストが通る
  - 関連 AC: AC-5, AC-6, AC-9, AC-10
- [x] **T-03: サービスとエンドポイント**
  - 変更対象: `backend/app/services/wardrobe_registry.py`, `backend/app/api/routes/wardrobe.py`, `backend/app/api/router.py`, `backend/tests/test_wardrobe_registry.py`, `backend/tests/test_wardrobe_api.py`
  - 完了条件: 画像の検証・解析・保存・一覧・削除・写真の取得・エラーの変換のテストが通る。ruff / mypy が通る
  - 関連 AC: AC-2, AC-6, AC-9, AC-10, AC-11, AC-12, AC-13

### フロントエンド

- [x] **T-04: パッケージの追加とモデル / Repository / PhotoPicker**
  - 変更対象: `frontend/pubspec.yaml`(`image_picker`), `frontend/lib/core/api_client.dart`, `frontend/lib/features/wardrobe/wardrobe_models.dart`, `wardrobe_repository.dart`, `photo_picker.dart`, `frontend/test/wardrobe_models_test.dart`
  - 完了条件: `fromJson` / `toJson` のテストが通る
  - 関連 AC: AC-13
- [x] **T-05: 一覧画面とタブ**
  - 変更対象: `frontend/lib/features/wardrobe/wardrobe_screen.dart`, `frontend/lib/main.dart`, `frontend/test/wardrobe_screen_test.dart`
  - 完了条件: タブ・一覧・0 件・削除のテストが通る
  - 関連 AC: AC-1, AC-8, AC-9
- [x] **T-06: 確認画面(解析・修正・除外・保存・取りやめ)**
  - 変更対象: `frontend/lib/features/wardrobe/wardrobe_review_screen.dart`, `frontend/test/wardrobe_review_screen_test.dart`
  - 完了条件: `dart format .` / `flutter analyze`(警告 0)/ `flutter test` が通る。Web 向けビルドが通る
  - 関連 AC: AC-2, AC-3, AC-4, AC-5, AC-6, AC-7, AC-11, AC-12

### 結合 / 仕上げ

- [x] **T-07: ドキュメント更新**
  - 変更対象: `README.md`, spec 005 / 006 の design.md(項目の追加と参照先の変更の注記)
  - 完了条件: README と各 spec の記述が実装と一致している
- [x] **T-08: 実 API での確認**
  - 完了条件: 実際の服の写真 1 枚で解析 → 保存 → 一覧 → エージェントのツールで参照 → 削除 を確認する
  - 結果(2026-09-30): サンプル画像 1 枚(ピンクの T シャツ)で解析 HTTP 200・約 8 秒。季節「春・夏・秋」・暖かさ「普通」・
    使う場面「普段着・ライブ・フェス」まで抽出された。保存 201 → 一覧 1 件 → 写真の取得 200 → エージェントの
    `list_wardrobe` が同じ服を返す → 削除 204 → 一覧 0 件・ツールは「インデックスが無い」。保存先は一時フォルダを使用
- [ ] **T-09: ブラウザでの目視確認**
  - 完了条件: Web アプリで写真の選択から保存・削除までを目視で確認する(ユーザーが実施)。確認後に `requirements.md` のステータスを `done` にする
