# 実装タスク: YouTube の MV からメタ情報を取得する

- 対応する設計: `./design.md`
- 進捗: 10 / 10

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 完了したら `- [ ]` を `- [x]` にする。

## タスク一覧

### バックエンド

- [x] **T-01: 設定の追加**
  - 変更対象: `backend/app/core/config.py`, `backend/.env.example`
  - 完了条件: `YOUTUBE_DATA_API_KEY` / `YOUTUBE_SEARCH_MAX_RESULTS` / `YOUTUBE_REGION_CODE` / `YOUTUBE_REQUEST_TIMEOUT` を `Settings` から読める
  - 関連 AC: —
- [x] **T-02: タイトルの分解**
  - 変更対象: `backend/app/services/mv_title.py`, `backend/tests/test_mv_title.py`
  - 完了条件: `uv run python -m pytest tests/test_mv_title.py` が通る(AC-5 の例・Topic・スラッシュの順序・分解不可)
  - 関連 AC: AC-5, AC-6
- [x] **T-03: URL の解析**
  - 変更対象: `backend/app/services/youtube.py`, `backend/tests/test_youtube_service.py`
  - 完了条件: 各 URL 形式から同じ動画 ID が取れ、動画以外の URL は `InvalidVideoUrlError`、MV 名は `None` になるテストが通る
  - 関連 AC: AC-2, AC-8
- [x] **T-04: YouTube API の呼び出しとエラーの正規化**
  - 変更対象: `backend/app/services/youtube.py`, `backend/tests/test_youtube_service.py`
  - 完了条件: MockTransport で videos / search の正常系、0 件、`items` 空、クォータ・認証・通信エラー、キー未設定、キーをヘッダで渡すことを確認するテストが通る
  - 関連 AC: AC-7, AC-9, AC-10, AC-11
- [x] **T-05: エンドポイント**
  - 変更対象: `backend/app/schemas/youtube.py`, `backend/app/api/routes/youtube.py`, `backend/app/api/router.py`, `backend/tests/test_youtube_api.py`
  - 完了条件: TestClient で 200(URL / MV 名)・400・404・422・502・503 を確認するテストが通る
  - 関連 AC: AC-1, AC-3, AC-4, AC-7, AC-8, AC-10

### フロントエンド

- [x] **T-06: モデル / Repository / エラー詳細の取り出し**
  - 変更対象: `frontend/lib/features/mv_lookup/mv_models.dart`, `frontend/lib/features/mv_lookup/mv_repository.dart`, `frontend/lib/core/api_client.dart`
  - 完了条件: `fromJson` と `ApiException.detail` のテストが通る
  - 関連 AC: AC-10
- [x] **T-07: MV 検索画面とナビゲーション**
  - 変更対象: `frontend/lib/features/mv_lookup/mv_lookup_screen.dart`, `frontend/lib/main.dart`, `frontend/test/mv_lookup_screen_test.dart`
  - 完了条件: `dart format .` / `flutter analyze`(警告 0)/ `flutter test` が通る
  - 関連 AC: AC-1, AC-3, AC-4, AC-6, AC-9, AC-10

### 結合 / 仕上げ

- [x] **T-08: ドキュメント更新**
  - 変更対象: `README.md`(技術スタック・構成・環境変数・認証の例外・使い方・トラブルシューティング・機能一覧)
  - 完了条件: README の記述と実装が一致している
- [x] **T-09: 実 API での疎通確認(API レベル)**
  - 完了条件: 実キーで MV 名検索 → 候補の URL で動画取得 → 存在しない ID → 無効なキー を順に実行し、期待どおりの応答になる
  - 結果(2026-09-29): 検索「YOASOBI アイドル」で 5 件、1 件目の分解は YOASOBI / アイドル、存在しない ID は 404、無効なキーは 502(認証)。
    httpx のリクエストログにキーが含まれないことも確認。候補 4 件目 `YOASOBI / Idol (「アイドル」English Ver. )` の分解不具合を見つけて修正した(design.md 6.2)
- [x] **T-10: ブラウザでの目視確認**
  - 完了条件: Web アプリの「MV 検索」で URL 入力と MV 名入力を 1 回ずつ行い、AC-1・AC-3・AC-4 の表示(サムネイルを含む)を目視で確認する(検索は 100 ユニット消費する)。確認後に `requirements.md` のステータスを `done` にする
