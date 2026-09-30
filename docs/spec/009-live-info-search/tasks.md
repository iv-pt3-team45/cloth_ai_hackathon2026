# 実装タスク: ライブ情報の検索と、MV 候補のその場での展開

- 対応する設計: `./design.md`
- 進捗: 9 / 10

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 完了したら `- [ ]` を `- [x]` にする。

## タスク一覧

### バックエンド

- [x] **T-01: グラウンディングの共通処理の切り出し**
  - 変更対象: `backend/app/services/grounding.py`(新規), `backend/app/services/culture.py`, `backend/tests/test_grounding.py`, `backend/tests/gemini_stub.py`, 既存の 008 のテスト
  - 完了条件: 008 のテストが変更前と同じく通る(API とふるまいは変えない)
  - 関連 AC: —
- [x] **T-02: 設定とスキーマ**
  - 変更対象: `backend/app/core/config.py`, `backend/.env.example`, `backend/app/schemas/live.py`
  - 完了条件: `LIVE_SEARCH_MODEL` / `LIVE_SEARCH_TIMEOUT` を読め、`query` と `date` が両方空のリクエストが検証で弾かれる
  - 関連 AC: AC-6
- [x] **T-03: ライブ情報の検索サービス**
  - 変更対象: `backend/app/services/live.py`, `backend/tests/test_live_service.py`
  - 完了条件: プロンプト・3 件への切り詰め・アーティスト名の除外・天気の整え方・日付の解釈・見つからない・エラーのテストが通る
  - 関連 AC: AC-5, AC-7, AC-8, AC-9, AC-10, AC-13, AC-15, AC-16
- [x] **T-04: エンドポイント**
  - 変更対象: `backend/app/api/routes/live.py`, `backend/app/api/router.py`, `backend/tests/test_live_api.py`
  - 完了条件: 200・422・502・503・504 のテストが通る。ruff / mypy が通る
  - 関連 AC: AC-6, AC-15, AC-16

### フロントエンド

- [x] **T-05: 候補のその場での展開**
  - 変更対象: `frontend/lib/features/mv_lookup/mv_lookup_screen.dart`, `frontend/test/mv_lookup_screen_test.dart`, `frontend/test/mv_lookup_culture_test.dart`
  - 完了条件: 展開・切り替え・閉じる・取得中のロックのテストが通る
  - 関連 AC: AC-1, AC-2, AC-3, AC-4
- [x] **T-06: ライブ情報のモデル / Repository / 出典表示の部品化**
  - 変更対象: `frontend/lib/features/mv_lookup/live_models.dart`, `live_repository.dart`, `grounding_footer.dart`, `culture_section.dart`, `frontend/test/live_models_test.dart`
  - 完了条件: `LiveSearchResult.fromJson` のテストが通り、008 の画面のテストも通る
  - 関連 AC: AC-11
- [x] **T-07: ライブを探す欄**
  - 変更対象: `frontend/lib/features/mv_lookup/live_section.dart`, `mv_lookup_screen.dart`, `utils.dart`, `frontend/test/mv_lookup_live_test.dart`, `mv_lookup_fakes.dart`
  - 完了条件: `dart format .` / `flutter analyze`(警告 0)/ `flutter test` が通る
  - 関連 AC: AC-5〜AC-15

### 結合 / 仕上げ

- [x] **T-08: ドキュメント更新**
  - 変更対象: `README.md`, spec 007 / 008 の design.md(画面の変更の反映)
  - 完了条件: README と各 spec の記述が実装と一致している
- [x] **T-09: 実 API での確認**
  - 完了条件: 実際のライブを検索し、候補・天気・出典が返ることを確認する(検索の課金が発生する)
  - 結果(2026-09-29): ① 「電光石火」+ YOASOBI で 3 件(名古屋・大阪・札幌)、約 25 秒。天気は候補ごとに
    「2023年4月5日 愛知県名古屋市 天気」などを検索し、tenki.jp などを出典にした実績になった。
    ② 日付 2027-01-10 + YOASOBI で台北ドームの公演 1 件、約 11 秒。天気は「予報はまだありません」。
    最初の実行で見つかった「天気を検索せずに値が返る」問題を直した(design.md 6.6)
- [ ] **T-10: ブラウザでの目視確認**
  - 完了条件: Web アプリで、候補の直下への展開・切り替え・閉じる、ライブの検索(ライブ情報 / 日付)・候補の選択・
    検索中の入力ロック・出典と検索候補の表示を目視で確認する(AC-1〜AC-5, AC-8, AC-9, AC-11, AC-12, AC-14)。
    確認後に `requirements.md` のステータスを `done` にする
