# 設計: 会場情報取得(F14)

- 対応する要件: `./requirements.md`
- ステータス: draft
- 更新日: 2026-10-05(画面から呼ぶAPIを追加、形態に「混在」を追加)

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | Gemini APIのGoogle検索グラウンディング(Grounding with Google Search)ツールを使い、会場名から会場情報をWeb検索させる | 採用 | 入力が「会場名(テキスト)」でURLを持たないため、URL Contextより適合する。既存コードもすべてGemini経由の統一アーキテクチャなので踏襲しやすい |
| B | Gemini APIのURL Contextツールを使う | 却下 | 入力に会場の公式ページURLが無い。F09が返す出典URLを使う余地はあるが、MVPでは対象外 |
| C | 会場情報専用の外部データベース/APIを別途契約する | 却下 | ハッカソンの残り期間に対して調査・契約コストが見合わない。MVP優先度もShouldであり、フォールバック(形態不明)が許容されている |

**構造化出力は使わない**: Google検索グラウンディングと構造化出力(`response_schema`)の併用は安全でないため、自由文の説明を取得し、キーワードマッチングで形態を分類する。住所抽出を廃止したことで、構造化出力を使う2回目のGemini呼び出しは無くなり、Geminiの呼び出しは1回になった。

## 2. 全体フロー

```
(呼び出し元: F20/Orchestratorからの直接呼び出し、またはチャットエージェントのFunction Calling)
  入力: venue_name(必須)、location / live_name / live_date(任意。F09のLiveCandidateから渡す想定)
        │
        ▼
get_venue_info(venue_name, *, location, live_name, live_date)   [backend/app/services/venue.py]
        │
        ├─ 1. _build_search_prompt(...)
        │      手がかりがあればプロンプトに含める(純粋関数)
        │
        ├─ 2. _search_venue(...)
        │      genai.Client.models.generate_content(
        │        tools=[Tool(google_search=GoogleSearch())]
        │      ) --> 会場(または公演)の座席形態に関する説明文
        │
        ├─ 3. _classify_format(raw_text)
        │      キーワードマッチングで "standing" / "seated" / "unknown" に分類
        │      (外部呼び出し無し。ユニットテストしやすくするため)
        │
        └─ 4. 例外発生時は catch し、format="unknown" / status="error" として返す
                │
                ▼
        VenueInfo(venue_name, format, summary, status, message)
```

## 3. API 設計

### `POST /api/v1/venue/lookup`(2026-10-05 追加)

画面(MV検索タブ)がライブを選んだ時点で呼ぶ。結果は確認タブに表示し、コーデ提案(spec 011)にも渡す。

リクエスト(選んだ `LiveCandidate` の値をそのまま送る。`venue` 以外は任意):

```json
{ "venue": "さいたまスーパーアリーナ", "location": "埼玉県さいたま市", "live_name": "ARENA TOUR", "date": "2023-06-04" }
```

レスポンス (200):

```json
{ "venue_name": "さいたまスーパーアリーナ", "format": "standing", "status": "ok", "message": "" }
```

- F14は失敗しても例外を投げない設計のため、失敗・時間切れも200で返す(`format: "unknown"`, `status: "error"`)。
- 会場名が空なら422。
- Geminiの説明文(`summary`)は返さない。グラウンディングの結果を画面にそのまま出す場合は検索候補の表示が必要になるため、画面に出すのは形態のラベルだけにする。
- ファイル: `app/schemas/venue.py`(新規)、`app/api/routes/venue.py`(新規)、`app/api/router.py` に登録。

### 呼び出し元

- 画面: 上記API(ライブを選んだ時点)。
- コーデ提案(spec 011)の `OutfitService.suggest`: 画面が形態を送ってきたら(unknown でも)それを使い、もう一度は調べない。送られてこなかったとき(調べている途中など)だけ、提案の前に調べる。
- チャットエージェントのツール(Function Calling。開発時の動作確認用)。

APIとコーデ提案は、どちらも `lookup_venue_info`(非同期の共通処理)経由で呼ぶ。`get_venue_info` は同期関数なので `asyncio.to_thread` で別スレッドで動かし、`venue_info_timeout`(既定30秒)で待ち時間を区切る。

## 4. データモデル

```python
class VenueFormat(StrEnum):   # app/schemas/venue.py(APIでも使うため schemas に置く)
    STANDING = "standing"
    SEATED = "seated"
    MIXED = "mixed"         # スタンディングと着席の両方がある(チケットの種別による)
    UNKNOWN = "unknown"

class VenueInfo(BaseModel):
    venue_name: str
    format: VenueFormat = VenueFormat.UNKNOWN
    summary: str = ""       # グラウンディングで得られた説明文
    status: Literal["ok", "error"] = "ok"
    message: str = ""       # status="error" のときの理由
```

**住所を持たない理由**: 当初はF15(天気情報取得)の入力として住所を取得していたが、天気は外部APIを使わずユーザーの任意入力とする方針になり、用途がなくなった。F09が所在地(都道府県・市区町村)を返しているため、画面表示にもそちらで足りる。住所抽出を外したことで、Gemini呼び出しが1回減り、コストと待ち時間も下がった。

会場形態の粒度は `standing` / `seated` / `mixed` / `unknown` の4値とする。説明文にスタンディングと着席の両方の言葉があれば `mixed`(混在)にする(2026-10-05。それまでは `unknown` にしていた)。「スタンディングではなく着席」のような否定の文でも `mixed` になる点は割り切り。チケットの種別をユーザーが選び直せるようにするのは将来の検討事項。

## 5. フロントエンド設計

該当なし。本specにフロントエンド変更は含まない。

## 6. バックエンド設計

- サービス: `backend/app/services/venue.py`
  - `_build_search_prompt(venue_name, location, live_name, live_date) -> str`: 検索プロンプトの組み立て。純粋関数。
  - `_search_venue(venue_name, settings, client, *, location, live_name, live_date) -> str`: Google検索グラウンディング付きでGeminiを呼び出し、説明文を返す。失敗時は `VenueSearchError`。
  - `_classify_format(raw_text: str) -> VenueFormat`: 外部呼び出し無しの純粋関数。
  - `get_venue_info(venue_name, settings, client, *, location, live_name, live_date) -> VenueInfo`: 上記を組み合わせ、例外を握りつぶして結果を返す(`wardrobe.py`と同じ、失敗してもエージェントを止めない方針)。`live_date` は `"YYYY-MM-DD"` 形式の文字列。
  - `build_venue_tools(settings) -> list[Callable[..., Any]]`: ADKツール登録用の薄いラッパー(`build_wardrobe_tools`と同じパターン)。手がかり3つも任意引数として公開する。
- ルータ追加: 無し(F14専用エンドポイントは作らない)。
- 設定追加(`backend/app/core/config.py`): `venue_info_model`(既定 `gemini-2.5-flash`)。

## 7. Gemini プロンプト設計

- モデル: `settings.venue_info_model`
- 手がかりの使い方:
  - 所在地: 会場名の後ろに括弧書きで添える(例: `「市民ホール」(愛知県名古屋市)`)。同名・複数拠点の会場の取り違えを防ぐ。
  - ライブ名・公演日: 渡された場合は「その公演の座席形態」を優先して調べさせる(座席形態は会場より公演ごとに決まることが多いため)。その公演の形態が分からなければ、会場の一般的な形態を答えさせる。
- 呼び出しは1回のみ(Google検索グラウンディング付き、構造化出力なし)。出力の自由文を `_classify_format` でキーワード判定する。
- 失敗時のフォールバック: Geminiの例外(タイムアウト・APIエラー等)は `get_venue_info` 側でcatchし、`VenueFormat.UNKNOWN` / `status="error"` として返す。呼び出し元を止めない。

## 8. エラーハンドリング / 非機能

- 異常系: Gemini呼び出し失敗、グラウンディング結果が空、キーワードにマッチしない、のいずれも例外にせず`unknown`として返す(requirements.md AC-2)。
- タイムアウト・リトライ: 既存の`media.py`等と同様、明示的なリトライは行わない(MVP優先度Shouldのため簡易実装で十分と判断)。
- ログ: 検索クエリ(会場名・所在地)をログに残す(個人情報は含まないため機微情報の懸念は無し)。

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend unit | `_classify_format` | pytest(様々な説明文パターンを与えて分類結果を検証。外部API呼び出し無し) |
| backend unit | `_build_search_prompt` | pytest(手がかり無し/所在地あり/ライブ名・公演日あり。住所を聞かないことも検証) |
| backend unit | `_search_venue` | pytest(genai.Clientをモック化し、手がかりがプロンプトに含まれることを検証) |
| backend unit | `get_venue_info` | pytest(`_search_venue`をスタブ化し、正常系・例外系・手がかりの受け渡しを検証) |
| backend unit | `lookup_venue_info` | pytest(手がかりの受け渡し、時間切れ・例外で unknown) |
| backend api | `POST /api/v1/venue/lookup` | 形態と手がかりの受け渡し、失敗でも200/unknown、説明文を返さない、会場名が空なら422 |
| frontend | MV検索タブ | ライブを選ぶと調べてsnapshotに入る、選び直したら古い結果を捨てる、失敗で不明、検索し直すとリセット |
| frontend | 確認タブ | 形態の表示(調べています…/各形態/不明)、提案時に送る・調べている途中なら送らない |
