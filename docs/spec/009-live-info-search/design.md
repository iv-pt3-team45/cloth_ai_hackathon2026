# 設計: ライブ情報の検索と、MV 候補のその場での展開

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-29

## 1. 設計方針

| 案 | ライブ情報の取得 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | spec 008 と同じく「① 検索ありで調べる(自由文)→ ② 検索なしで JSON に整理する」の 2 回 | 採用 | 出典を確実に得られる(検索と JSON 出力を同時に使うと出典が空になる事例がある。spec 008 design 0.)。実装とテストの形も 008 と揃う |
| B | 1 回の呼び出しで検索 + JSON | 却下 | 同上 |

| 案 | 共通処理 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | グラウンディングの共通処理(検索ありの呼び出し・出典の取り出し・出典番号の差し込み・クォータ判定)を `app/services/grounding.py` に切り出し、008 と 009 で使う | 採用 | 同じ処理を 2 か所に持たない。008 の API の形は変えない |
| B | 009 で 008 のコードをコピーする | 却下 | 修正が 2 か所に分かれる |

| 案 | 天気の扱い | 採否 | 理由 |
| --- | --- | --- | --- |
| A | Gemini に調べさせ、**あり得ない値はサーバで取り除く**(未来の日付の「実績」、予報の出ない先の日付の値) | 採用 | 要件「推測で埋めない」を、モデルの指示だけに頼らずに守るため |
| B | Gemini の出力をそのまま使う | 却下 | 2 週間より先の「予報」など、根拠の無い値が混ざるおそれがある |

## 2. 全体フロー

```
MvLookupScreen
  ├─ (A) 候補をタップ → その候補の直下に展開 → 動画情報(007)→ カルチャー情報(008)を自動取得
  └─ (B) 「ライブを探す」: ライブ情報 / 日付 → [検索]
        → 表示中のアーティスト(008 の特定結果 > 007 の分解結果)を artist として添える
        → LiveRepository.search(query, date, artist)
        → POST /api/v1/live/search
        → live.py(routes): LiveSearchRequest で検証(query と date が両方空なら 422)
        → LiveService.search()
            ├─ grounded_research(prompt)   ① 検索あり・自由文(今日の日付を渡し、過去 / 未来を判断させる)
            └─ _structure(本文)            ② 検索なし・JSON(最大 3 件)
            → 天気の整合性チェック・3 件に切り詰め・アーティスト名の除外
        → LiveSearchResponse
        → 候補カードを最大 3 件表示。タップで 1 件を選ぶ(強調表示)
```

## 3. API 設計

### `POST /api/v1/live/search`

リクエスト:

```json
{ "query": "電光石火", "date": "2023-06-04", "artist": "YOASOBI" }
```

| フィールド | 型 | 内容 |
| --- | --- | --- |
| `query` | `str`(前後の空白を除去。0〜200 文字) | ライブ名・ツアー名・会場などのキーワード。省略可 |
| `date` | `date \| null`(`YYYY-MM-DD`) | 公演日。省略可 |
| `artist` | `str \| null`(0〜200 文字) | 表示中の動画で分かっているアーティスト名。**指定した場合、候補のアーティスト名は取得しない** |

`query` と `date` が両方空なら 422(AC-6。フロントでも API を呼ぶ前に止める)。

レスポンス (200)(値は説明用のダミー):

```json
{
  "artist": "YOASOBI",
  "found": true,
  "message": "",
  "candidates": [
    {
      "index": 1,
      "artist": null,
      "live_name": "YOASOBI ARENA TOUR 2023 \"電光石火\"",
      "venue": "さいたまスーパーアリーナ",
      "location": "埼玉県さいたま市",
      "date": "2023-06-04",
      "weather": { "kind": "actual", "summary": "晴れ", "high_c": 27.0, "low_c": 18.0, "precipitation_chance": null },
      "source_indices": [1, 2]
    }
  ],
  "sources": [ { "index": 1, "title": "…", "url": "https://…", "domain": "…" } ],
  "search_suggestions_html": "…",
  "web_search_queries": ["…"],
  "model": "gemini-3.5-flash-lite"
}
```

- `artist`: リクエストで受け取ったアーティスト名(無ければ空)。候補の `artist` は、これが空のときだけ入る(AC-7 / AC-8)。
- `candidates` は最大 3 件。見つからなければ `found=false`・`candidates=[]`・`message` に理由(AC-13)。
- `weather.kind`: `actual`(実績)/ `forecast`(予報)/ `not_yet`(予報はまだ無い)/ `unknown`(不明)。数値は分からなければ `null`。

エラー(spec 008 と同じ対応):

| ステータス | 条件 | 例外 |
| --- | --- | --- |
| 422 | 入力の形式が不正、`query` と `date` が両方空 | (Pydantic) |
| 502 | Gemini の呼び出しに失敗、応答を解釈できない | `LiveSearchError` |
| 503 | Gemini のクォータ超過 | `LiveSearchQuotaError` |
| 504 | `live_search_timeout` を超えた | `LiveSearchTimeoutError` |

## 4. データモデル

### バックエンド: `app/schemas/live.py`

| モデル | フィールド |
| --- | --- |
| `LiveSearchRequest` | `query: str`、`date: date \| None`、`artist: str \| None`(両方空の検証つき) |
| `LiveWeather` | `kind: Literal["actual", "forecast", "not_yet", "unknown"]`、`summary: str`、`high_c` / `low_c: float \| None`、`precipitation_chance: int \| None` |
| `LiveCandidate` | `index: int`、`artist: str \| None`、`live_name` / `venue` / `location: str`、`date: date \| None`、`weather: LiveWeather`、`source_indices: list[int]` |
| `LiveSearchResponse` | `artist` / `found` / `message` / `candidates` / `sources`(spec 008 の `Source`)/ `search_suggestions_html` / `web_search_queries` / `model` |

モデルの構造化出力(`_LiveSearchOutput` など)は services 内に置き、詰め替える(spec 008 と同じ理由)。
`weather.kind` と `date` は構造化出力では文字列で受け、サーバで検証する(想定外の値で応答全体の解釈が失敗しないように)。

### フロントエンド: `lib/features/mv_lookup/live_models.dart`

`LiveSearchResult` / `LiveCandidate` / `LiveWeather`。出典は spec 008 の `CultureSource` を使う。

## 5. フロントエンド設計

### 5.1 (A) 候補のその場での展開(spec 007 / 008 の画面の変更)

- 状態: `_expandedVideoId`(展開中の候補の動画 ID)を追加し、`_video`(取得した動画情報)と組み合わせる。
- 候補のタップ:

| 状況 | 動作 |
| --- | --- |
| 取得中(`_busy`) | 反応しない(AC-4) |
| 展開中の候補をタップ | 閉じる(`_expandedVideoId` / `_video` / カルチャー情報を消す)(AC-3) |
| 別の候補をタップ | その候補を展開し、動画情報 → カルチャー情報を取得し直す(AC-1 / AC-2) |

- 展開中の候補は色を変え、アイコンを `expand_more`、それ以外は `chevron_right` にする。
- 展開部分には、動画情報の取得中は `LinearProgressIndicator`、取得後は動画情報とカルチャー情報(spec 008 の `CultureSection`)を出す。
- 動画情報の取得に失敗したら展開を閉じ、上部のバナーにエラーを出す。
- 「候補一覧に戻る」ボタンは削除する。URL を入力した場合(候補が無い)は今までどおり一覧の代わりに表示する。

### 5.2 (B) ライブ情報の検索(`LiveSection`)

MV の結果の下に「ライブを探す」カードを置く(MV を調べる → アーティストを知る → ライブを探す、という上から下の流れに合わせる)。

- 入力: ライブ情報(`TextField`)、日付(カレンダーから選ぶボタン + 消すボタン)、検索ボタン。
- アーティストの表示: 表示中の動画でアーティストが分かっていれば「アーティスト: YOASOBI(表示中の動画から)」、
  分かっていなければ「アーティストは入力から特定します」。
- 表示中のアーティスト: カルチャー情報で特定済み(`identified`)ならその名前、無ければ動画のタイトルを分解できた場合の `artist`、どちらも無ければ無し。
- 結果の表示:

| 状況 | 表示 |
| --- | --- |
| 入力が両方空で検索 | 「ライブ情報か日付を入力してください」。API は呼ばない(AC-6) |
| 取得中 | `CircularProgressIndicator` と「ライブ情報を調べています」 |
| 失敗 | エラーと「再試行」(同じ条件で呼び直す)(AC-15) |
| 見つからない | 「該当するライブが見つかりませんでした」と `message`(AC-13) |
| 完了 | 候補カード(最大 3 件)・出典・検索候補(AC-9 / AC-11) |

- 候補カード: ライブ名 / アーティスト名(`artist` があるときだけ)/ 場所 / 日付 / 天気。
  天気は「晴れ / 最高 27℃ / 最低 18℃ / 降水確率 20%」に種類のラベル(実績 / 予報)を添える。
  `not_yet` は「予報はまだありません」、`unknown` は「不明」(AC-10)。
- 候補のタップで選択し、選んだカードは色と枠線・チェックアイコンで強調する(AC-12)。新しく検索したら選択は消える。
- 出典と検索候補は spec 008 の表示を部品化した `GroundingFooter`(新規。`culture_section.dart` から切り出す)で出す。

### 5.3 入力のロック

`_busy = 動画情報の取得中 || カルチャー情報の取得中 || ライブ情報の取得中`。
この間は MV の入力欄・検索ボタン・候補のタップ・ライブの入力欄・日付ボタン・検索ボタンをすべて無効にする(AC-4 / AC-14)。

### 5.4 日付の選択

`showDatePicker` を使う(範囲: 2000 年〜今日の 3 年後)。アプリに日本語のローカライズを入れていないため、
カレンダーの表記は英語になる(ローカライズの追加は依存パッケージの追加になるため今回は行わない)。
選んだ日付は画面上で `2023/06/04` のように表示する。

## 6. バックエンド設計

- ルータ: `backend/app/api/routes/live.py`(新規)。`app/api/router.py` に登録する。
- サービス: `backend/app/services/live.py`(新規)。
- 共通処理: `backend/app/services/grounding.py`(新規。spec 008 の `culture.py` から移す)。
- スキーマ: `backend/app/schemas/live.py`(新規)。

### 6.1 `grounding.py`(008 から切り出す)

| 要素 | 内容 |
| --- | --- |
| `WebResearch` | 本文(出典番号入り)・出典・検索候補 HTML・検索クエリ |
| `grounded_research(client, model, prompt)` | Google 検索ありで呼び、`WebResearch` を返す(自動関数呼び出しは無効) |
| `extract_research` / `insert_citations` / `valid_indices` | spec 008 のものを移す |
| `is_quota_error(exc)` | `APIError` の 429 / `RESOURCE_EXHAUSTED` を判定する |

`culture.py` はこれらを使うように変える(008 の API とふるまいは変えない)。

### 6.2 ① 調べる(プロンプト)

- 条件: アーティスト(指定されていれば「このアーティストの公演だけ」)、ライブ情報、日付、**今日の日付(日本時間)**。
- 各候補について: (アーティスト名)・ライブ名・会場名と所在地・公演日(1 候補 1 日)・当日の天気。
- 天気: **候補ごとに「公演日 + 所在地 + 天気」で検索させる**(例: 「2023年6月3日 さいたま市 天気」)。
  公演日が今日より前なら会場付近の実際の天気、今日以降で予報が出ていれば予報、出ていなければ「予報はまだありません」。
  検索で確認できなければ「不明」。
- 見つからなければ「見つかりませんでした」。Web で確認できた内容だけを書き、分からない項目は「不明」。推測で埋めない。

### 6.3 ② 整理する

- `response_schema=_LiveSearchOutput`・`temperature=0`・検索なし。最大 3 件。
- 出典番号(`[n]`)から候補ごとの `source_indices` を入れさせる。天気の根拠の番号は `weather.source_indices` に分けて入れさせ、
  天気の文に出典番号が無ければ `kind=unknown` にさせる。

### 6.4 サーバでの整え方

| 処理 | 内容 |
| --- | --- |
| 件数 | 先頭 3 件に切り詰め、`index` を 1 から振り直す |
| アーティスト名 | リクエストで `artist` を受け取った場合は、候補の `artist` を `null` にする |
| 日付 | `YYYY-MM-DD` として解釈できなければ `null` |
| 天気の種類 | 想定外の値は `unknown` |
| 未来の「実績」 | 公演日が今日より後で `actual` なら `unknown` にし、数値を消す |
| 予報の出ない先 | 公演日が今日から `FORECAST_HORIZON_DAYS`(14 日)より先なら `not_yet` にし、数値を消す |
| 根拠の無い天気 | `actual` / `forecast` でも、実在する出典(`weather.source_indices`)が無ければ `unknown` にし、数値を消す |
| 実績の降水確率 | 降水確率は予報の値のため、`actual` では `null` にする |
| 候補の出典番号 | 候補の `source_indices` と天気の `source_indices` を合わせて示す |
| 出典番号 | 実在する出典だけを残す |
| 「不明」の文字 | 空として扱う(spec 008 と同じ) |

「今日」は日本時間(UTC+9 の固定オフセット)で求める。テストで差し替えられるよう、`LiveService` に日付の関数を渡せるようにする。

### 6.5 設定

| 設定 | 既定値 | 用途 |
| --- | --- | --- |
| `live_search_model` | `gemini-3.5-flash-lite` | ライブ情報の検索に使うモデル(Google 検索に対応したもの) |
| `live_search_timeout` | `120` | ①② 全体の待ち時間の上限(秒) |

### 6.6 実 API での確認で見つかった点(2026-09-29)

| 見つかった点 | 対応 |
| --- | --- |
| 最初のプロンプトでは天気を検索せず(検索クエリはライブ名だけ)、「最高 20.3℃」のような根拠の無い値が返った | 天気を候補ごとに検索するよう指示し、出典の無い天気はサーバで `unknown` にする(6.2〜6.4)。修正後は「2023年4月5日 愛知県名古屋市 天気」などを検索し、tenki.jp などを出典にした値になった |
| 過去の公演に「降水確率 0%」が付いていた | 実績では降水確率を捨てる(6.4) |
| 関数ツールを渡さない呼び出しでも、SDK が自動関数呼び出し(AFC)の警告を出していた | すべての呼び出しで AFC を無効にする(`grounding.NO_AFC`。spec 008 の呼び出しも同様) |

## 7. エラーハンドリング / 非機能

- spec 008 と同じ: 自動のリトライはしない、結果は保存しない、ログには例外の型だけを残す。
- 1 回の検索で呼ぶ Gemini は 2 回(検索ありは 1 回)。

## 8. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend unit | `grounding.py` | 008 のテストを移す(出典の取り出し・出典番号の差し込み) |
| backend unit | `LiveService` | フェイクのクライアントで: プロンプト(アーティスト指定あり / なし・今日の日付)、3 件への切り詰め、アーティスト名の除外、天気の整え方(出典の無い天気・実績の降水確率を含む)、日付の解釈、見つからない、クォータ・タイムアウト・その他のエラー |
| backend api | ルータ | 200・422(両方空)・502・503・504 |
| frontend | モデル | `LiveSearchResult.fromJson` |
| frontend | 画面 (A) | 候補の直下に展開 / 別の候補で切り替え / 同じ候補で閉じる / 取得中は他の候補を押せない |
| frontend | 画面 (B) | 空の入力 / 検索結果の表示と天気の種類 / 表示中のアーティストの受け渡し / 選択の強調 / 見つからない / 失敗と再試行 / 取得中のロック |
| 手動 | 実 API | 実際のライブを 1 回検索する(検索の課金が発生する) |
