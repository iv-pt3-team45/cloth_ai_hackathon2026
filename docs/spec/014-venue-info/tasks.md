# 実装タスク: 会場情報取得(F14)

- 対応する設計: `./design.md`
- 進捗: 16 / 18(画面から呼ぶAPI・確認タブの表示・混在を追加。残りは疎通確認)

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 完了したら `- [ ]` を `- [x]` にする。

## タスク一覧

### バックエンド

- [x] **T-01: `services/venue.py` の骨格作成(データモデル定義)**
  - 変更対象: `backend/app/services/venue.py`(新規)
  - 内容: `VenueFormat`(Enum: standing/seated/unknown)、`VenueInfo`(BaseModel)を定義する
  - 完了条件: `uv run python -c "from app.services.venue import VenueInfo, VenueFormat"` がエラーなく通る
  - 関連 AC: -(準備タスク)

- [x] **T-02: `_classify_format` の実装とユニットテスト**
  - 変更対象: `backend/app/services/venue.py`、`backend/tests/test_venue.py`(新規)
  - 内容: 説明文(文字列)からキーワードマッチングで `VenueFormat` を判定する純粋関数。外部API呼び出し無し
  - 完了条件: `uv run python -m pytest backend/tests/test_venue.py -k classify` が通る(「スタンディング」「着席」「該当語なし」など複数パターンを検証)
  - 関連 AC: AC-1, AC-3

- [x] **T-03: `_search_venue` の実装(Gemini + Google検索グラウンディング)と技術検証**
  - 変更対象: `backend/app/services/venue.py`
  - 内容: `genai.Client.models.generate_content()` に `tools=[Tool(google_search=GoogleSearch())]` を指定して会場の説明文を取得する
  - 完了条件: `uv run python scripts/run_agent.py`とは別に、単発の検証スクリプトまたはREPLで実際に既知の会場名(例: "日本武道館")を渡し、それらしい説明文が返ってくることを目視確認する。design.mdに書いた技術リスク(構造化出力との併用可否)は今回検証しない(採用していないため無関係)ことを確認する
  - 関連 AC: AC-1

- [x] **T-04: `get_venue_info` の実装(結合・例外処理)とユニットテスト**
  - 変更対象: `backend/app/services/venue.py`、`backend/tests/test_venue.py`
  - 内容: `_search_venue` と `_classify_format` を結合し、例外発生時は `status="error"` / `format=unknown` を返す(呼び出し元を止めない)
  - 完了条件: `uv run python -m pytest backend/tests/test_venue.py` が通る(正常系・Gemini呼び出し失敗時の異常系の両方をモックで検証)
  - 関連 AC: AC-1, AC-2

- [x] **T-05: `build_venue_tools` の実装(ADKツールラッパー)**
  - 変更対象: `backend/app/services/venue.py`
  - 内容: `build_wardrobe_tools` と同じパターンで、`get_venue_info` をADKのFunction Callingツールとして登録できる形にラップする
  - 完了条件: `agent.py` の `tools=[...]` に一時的に組み込んでみて、`uv run python scripts/run_agent.py -m "日本武道館の会場情報を教えて"` のような対話でツールが呼ばれることを確認する
  - 関連 AC: AC-3

- [x] **T-06: 設定追加**
  - 変更対象: `backend/app/core/config.py`(63行目付近、`cloth_index_model`と同じセクション)
  - 内容: `venue_info_model: str = "gemini-2.5-flash"` を追加する
  - 完了条件: `uv run python -c "from app.core.config import get_settings; print(get_settings().venue_info_model)"` が通る
  - 関連 AC: -(準備タスク)

- [x] **T-08: `_extract_address` の実装とユニットテスト**(T-11で廃止)
  - 変更対象: `backend/app/services/venue.py`、`backend/tests/test_venue.py`
  - 内容: `_search_venue`の結果から住所を抽出する。構造化出力(`response_schema`)を使用し、toolsは付けない
  - 完了条件: `uv run python -m pytest backend/tests/test_venue.py -k address` が通る(住所が取れる場合・取れない場合をモックで検証)
  - 関連 AC: AC-4

- [x] **T-09: `get_venue_info` に住所抽出を組み込む**(T-11で廃止)
  - 変更対象: `backend/app/services/venue.py`、`backend/tests/test_venue.py`
  - 内容: `get_venue_info`が`_extract_address`も呼び、`VenueInfo.address`に反映する。住所抽出の失敗は致命的にしない(`address=""`のまま継続)
  - 完了条件: `uv run python -m pytest backend/tests/test_venue.py` が通る
  - 関連 AC: AC-4

### 結合 / 仕上げ

- [x] **T-10: 疎通確認(位置情報)**(T-11で廃止)
  - 完了条件: `uv run python scripts/run_agent.py -v` で会場名を含む質問をし、`VenueInfo.address`にそれらしい住所が入ることを確認する
  - 関連 AC: AC-4

- [x] **T-07: 疎通確認**
  - 完了条件: `uv run python scripts/run_agent.py` で実際に会場名を含む質問を投げ、会場情報(形態)を含む応答が返ってくることを確認する。異常系(存在しない会場名など)でもエラーで落ちず「形態不明」の応答になることも確認する
  - 関連 AC: AC-1, AC-2

### 2026-10-02 追加分(住所抽出の廃止・検索の手がかりの追加)

- [x] **T-11: 住所抽出の廃止**
  - 変更対象: `backend/app/services/venue.py`、`backend/tests/test_venue.py`
  - 内容: `_extract_address`・`_AddressExtraction`・`VenueInfo.address` を削除する(天気APIを使わない方針になり用途が無くなったため)。ツールのdocstringからも住所の記述を外す
  - 完了条件: `uv run python -m pytest` が通り、`venue.py` に住所関連のコードが残っていない
  - 関連 AC: AC-4(廃止)

- [x] **T-12: 検索の手がかり(所在地・ライブ名・公演日)の追加**
  - 変更対象: `backend/app/services/venue.py`、`backend/tests/test_venue.py`
  - 内容: `_build_search_prompt` を追加し、`_search_venue` / `get_venue_info` / ADKツールに任意引数 `location` / `live_name` / `live_date` を追加する。未指定でも従来どおり動く
  - 完了条件: プロンプト組み立て・手がかりの受け渡しのユニットテストが通る
  - 関連 AC: AC-5

- [ ] **T-13: 疎通確認(手がかりあり)**
  - 完了条件: `uv run python scripts/run_agent.py` で、同名・複数拠点の会場(例: 市民ホールに所在地を添える)や、ライブ名・公演日を含む質問をして、期待どおりの会場・形態が返ることを確認する
  - 関連 AC: AC-5

- [x] **T-14: コーデ提案(spec 011)への組み込み**
  - 変更対象: `backend/app/services/outfit.py`、`backend/app/core/config.py`(`venue_info_timeout`)、`backend/tests/outfit_stub.py`、`backend/tests/test_outfit_service.py`
  - 内容: 提案の前に `get_venue_info` を呼び、形態をプロンプトに足す。失敗・時間切れ・不明なら足さない
  - 完了条件: `uv run python -m pytest` が通る
  - 関連 AC: AC-6

- [ ] **T-15: Docker経由での画面確認**
  - 完了条件: Docker Composeでアプリを起動し、MV検索 → ライブ選択 → 確認タブに「会場の形態」が出ること、「コーデを提案」を押して形態を踏まえた提案が返ることを確認する
  - 関連 AC: AC-6

### 2026-10-05 追加分(ライブを選んだ時点で形態を調べる・混在)

- [x] **T-16: 形態に「混在」を追加**
  - 変更対象: `backend/app/schemas/venue.py`(新規。`VenueFormat` を移動)、`backend/app/services/venue.py`、`backend/app/services/outfit.py`(表記と指示文)
  - 完了条件: 両方のキーワードがある説明文が `mixed` になるテストが通る
  - 関連 AC: AC-8

- [x] **T-17: `POST /api/v1/venue/lookup` の追加と共通化**
  - 変更対象: `backend/app/api/routes/venue.py`(新規)、`backend/app/api/router.py`、`backend/app/services/venue.py`(`lookup_venue_info`)、`backend/app/services/outfit.py`、`backend/app/schemas/outfit.py`(`venue_format`)、`backend/tests/test_venue_api.py`(新規)ほか
  - 完了条件: `uv run python -m pytest` が通る
  - 関連 AC: AC-6, AC-7

- [x] **T-18: 画面(ライブを選んだら調べる・確認タブに表示・提案に送る)**
  - 変更対象: `frontend/lib/features/mv_lookup/venue_models.dart`・`venue_repository.dart`(新規)、`mv_lookup_screen.dart`、`mv_lookup_snapshot.dart`、`frontend/lib/features/outfit/confirm_screen.dart`・`outfit_repository.dart`、テスト
  - 完了条件: `flutter analyze` と `flutter test` が通る(フロントのコンテナかCIで実行)
  - 関連 AC: AC-7

> ドキュメント更新(README/requirements.mdステータス変更)は、リポジトリへのコミット方針が未確定のため、本タスク一覧には含めない。
