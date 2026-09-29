# 実装タスク: アーティストのカルチャー情報を Gemini で調べて整理する

- 対応する設計: `./design.md`
- 進捗: 8 / 9

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 完了したら `- [ ]` を `- [x]` にする。

## タスク一覧

### バックエンド

- [x] **T-01: 設定とスキーマ**
  - 変更対象: `backend/app/core/config.py`, `backend/.env.example`, `backend/app/schemas/culture.py`
  - 完了条件: `CULTURE_MODEL` / `CULTURE_TIMEOUT` を `Settings` から読め、`CultureRequest` / `CultureResponse` が定義されている
  - 関連 AC: —
- [x] **T-02: 出典の取り出しと出典番号の差し込み**
  - 変更対象: `backend/app/services/culture.py`, `backend/tests/test_culture_service.py`
  - 完了条件: グラウンディングのメタデータから出典・検索候補・検索クエリを取り出し、日本語の本文に `[n]` を正しく差し込むテストが通る
  - 関連 AC: AC-4
- [x] **T-03: ①②③ の呼び出しとエラーの正規化**
  - 変更対象: `backend/app/services/culture.py`, `backend/tests/test_culture_service.py`
  - 完了条件: フェイクのクライアントで、正常系・特定できない・③ だけの失敗・①② の失敗・クォータ・タイムアウト・範囲外の出典番号・プロンプトの組み立てのテストが通る
  - 関連 AC: AC-3, AC-5, AC-6, AC-7, AC-8, AC-9, AC-11
- [x] **T-04: エンドポイント**
  - 変更対象: `backend/app/api/routes/culture.py`, `backend/app/api/router.py`, `backend/tests/test_culture_api.py`
  - 完了条件: TestClient で 200・422・502・503・504 を確認するテストが通る。ruff / mypy が通る
  - 関連 AC: AC-9, AC-11

### フロントエンド

- [x] **T-05: モデル / Repository / 検索候補の表示**
  - 変更対象: `frontend/lib/features/mv_lookup/culture_models.dart`, `culture_repository.dart`, `search_suggestions_view*.dart`, `frontend/test/culture_models_test.dart`
  - 完了条件: `CultureReport.fromJson` のテストが通る。Web では検索候補の HTML を、それ以外では検索クエリを表示する
  - 関連 AC: AC-4
- [x] **T-06: カルチャー情報の表示と、取得中の入力ロック**
  - 変更対象: `frontend/lib/features/mv_lookup/culture_section.dart`, `mv_lookup_screen.dart`, `frontend/test/mv_lookup_culture_test.dart`, `mv_lookup_screen_test.dart`, `mv_lookup_fakes.dart`
  - 完了条件: `dart format .` / `flutter analyze`(警告 0)/ `flutter test` が通る
  - 関連 AC: AC-1, AC-2, AC-3, AC-5, AC-6, AC-8, AC-9, AC-10

### 結合 / 仕上げ

- [x] **T-07: ドキュメント更新**
  - 変更対象: `README.md`(構成・環境変数・使い方・トラブルシューティング・機能一覧)
  - 完了条件: README の記述と実装が一致している
- [x] **T-08: 実 API での確認**
  - 完了条件: 実際の MV で 1 回実行し、出典・検索候補・この MV の衣装が返ることを確認する(検索の課金が発生する)
  - 結果(2026-09-29): YOASOBI「アイドル」の MV で HTTP 200・約 50 秒。アーティストを特定し、経歴・ジャンル・代表曲、
    出典 24 件、検索候補の HTML、MV の衣装 7 着分が返った。検索クエリは 6 件
    (「YOASOBI アーティスト情報」「YOASOBI ファッション スタイル 特徴」など)。
    出典のタイトルにドメイン名が入る点と、SDK の不要な警告に対応した
- [ ] **T-09: ブラウザでの目視確認**
  - 完了条件: Web アプリで URL 入力と候補の選択を 1 回ずつ行い、自動で取得が始まること・取得中の入力ロック・
    各セクションと出典・**検索候補の HTML の表示**を目視で確認する(AC-1〜AC-5)。確認後に `requirements.md` のステータスを `done` にする
