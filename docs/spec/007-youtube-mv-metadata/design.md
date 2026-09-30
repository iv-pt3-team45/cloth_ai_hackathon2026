# 設計: YouTube の MV からメタ情報を取得する

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-29

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | 入力をそのままバックエンドに送り、URL か MV 名かの判定もバックエンドで行う。エンドポイントは 1 本 | 採用 | 判定ロジックがフロントとバックに重複しない。候補を選んだときも、候補の URL を同じエンドポイントに送るだけで済む |
| B | 「動画取得」と「検索」の 2 本に分け、フロントが URL かどうかを判定する | 却下 | URL の判定がフロントとバックの 2 か所に必要になり、食い違いの原因になる |

| 案 | YouTube API の呼び出し方 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | `httpx` で REST API(`videos` / `search`)を直接呼ぶ | 採用 | 使う API は 2 つだけ。httpx は google-genai の依存として既に入っている(0.28.1)。テストでは `httpx.MockTransport` に差し替えられる |
| B | `google-api-python-client` を使う | 却下 | 依存が大きく、呼び出す API が 2 つだけなら得るものが少ない |

| 案 | API キーの渡し方 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | リクエストヘッダ `X-Goog-Api-Key` | 採用 | ルートロガーが INFO のため、httpx がリクエスト URL をログに出す。クエリ(`?key=`)で渡すとキーがログに残る |
| B | クエリパラメータ `key=` | 却下 | 上記のとおりキーがログに漏れる |

## 2. 全体フロー

```
MvLookupScreen(入力: URL または MV 名)
  → MvRepository.lookup(query)
  → POST /api/v1/youtube/lookup  {"query": "..."}
  → youtube.py(routes): LookupRequest で検証(空文字は 422)
  → YouTubeService.lookup(query)
      ├─ extract_video_id(query)
      │    ├─ URL でない            → MV 名として search()
      │    ├─ YouTube の動画 URL    → get_video(video_id)
      │    └─ それ以外の URL        → InvalidVideoUrlError(API は呼ばない)
      ├─ get_video(): GET /youtube/v3/videos?part=snippet&id=<ID>
      │    └─ parse_title(タイトル, チャンネル名) でアーティスト名・曲名に分解
      └─ search():   GET /youtube/v3/search?part=snippet&type=video&q=<MV名>&maxResults=5
  → LookupResponse
       - URL:   {"input_type": "url",     "video": {...}, "candidates": []}
       - MV 名: {"input_type": "keyword", "video": null,  "candidates": [...]}
  → 画面に結果 / 候補一覧を表示

候補を選んだとき:
  → 候補の URL を query にして同じ POST /api/v1/youtube/lookup を呼ぶ(= URL 入力と同じ経路)
```

## 3. API 設計

### `POST /api/v1/youtube/lookup`

(以下の動画 ID・日付・概要欄は説明用のダミー)

リクエスト:

```json
{ "query": "https://youtu.be/xxxxxxxxxxx?si=xxxx" }
```

- `query`: URL または MV 名。前後の空白は除去し、除去後に空なら 422。最大 500 文字。

レスポンス (200) — URL を入力した場合:

```json
{
  "input_type": "url",
  "video": {
    "video_id": "xxxxxxxxxxx",
    "url": "https://www.youtube.com/watch?v=xxxxxxxxxxx",
    "artist": "YOASOBI",
    "song_title": "アイドル",
    "title_parsed": true,
    "title": "YOASOBI「アイドル」 Official Music Video",
    "channel_title": "Ayase / YOASOBI",
    "published_at": "2023-01-01T00:00:00Z",
    "thumbnail_url": "https://i.ytimg.com/vi/xxxxxxxxxxx/hqdefault.jpg",
    "description": "..."
  },
  "candidates": []
}
```

レスポンス (200) — MV 名を入力した場合:

```json
{
  "input_type": "keyword",
  "video": null,
  "candidates": [
    {
      "video_id": "xxxxxxxxxxx",
      "url": "https://www.youtube.com/watch?v=xxxxxxxxxxx",
      "title": "YOASOBI「アイドル」 Official Music Video",
      "channel_title": "Ayase / YOASOBI",
      "published_at": "2023-01-01T00:00:00Z",
      "thumbnail_url": "https://i.ytimg.com/vi/xxxxxxxxxxx/hqdefault.jpg"
    }
  ]
}
```

- 検索結果が 0 件でも 200(`candidates: []`)。「見つからない」の表示はフロントが行う(AC-9)。

エラー:

| ステータス | 条件 | 対応する例外 | ボディ |
| --- | --- | --- | --- |
| 400 | YouTube の動画以外の URL(再生リスト・チャンネル・他サイト) | `InvalidVideoUrlError` | `{"detail": "..."}` |
| 404 | 動画が存在しない・非公開・削除済み(`videos` の `items` が空) | `VideoNotFoundError` | `{"detail": "..."}` |
| 422 | `query` が空 / 長すぎる | (Pydantic) | FastAPI 標準 |
| 502 | 認証エラー・通信エラー・その他の API エラー・キー未設定 | `YouTubeApiError` とその派生 | `{"detail": "..."}` |
| 503 | クォータ超過(時間をおけば回復する) | `YouTubeQuotaError` | `{"detail": "..."}` |

`detail` の文言で原因の種類(クォータ / 認証 / 通信)が分かるようにする(AC-10)。

## 4. データモデル

### バックエンド: `app/schemas/youtube.py`

| モデル | フィールド |
| --- | --- |
| `LookupRequest` | `query: str`(strip 後 1〜500 文字) |
| `VideoInfo` | `video_id` / `url` / `artist` / `song_title` / `title_parsed: bool` / `title` / `channel_title` / `published_at: datetime \| None` / `thumbnail_url` / `description` |
| `VideoCandidate` | `video_id` / `url` / `title` / `channel_title` / `published_at: datetime \| None` / `thumbnail_url` |
| `LookupResponse` | `input_type: Literal["url", "keyword"]` / `video: VideoInfo \| None` / `candidates: list[VideoCandidate]` |

- `VideoInfo` が後続の公演情報の調査に渡す単位になる(ゴール「1 つのデータ構造」)。
- YouTube API のレスポンス(生の JSON)は services 内で辞書のまま読み、上記に詰め替える(schemas を外部 API のモデルと兼ねない)。

### フロントエンド: `lib/features/mv_lookup/mv_models.dart`

`MvVideo` / `MvCandidate` / `MvLookupResult` を上記と 1 対 1 で持ち、`fromJson` で組み立てる。

## 5. フロントエンド設計

- 画面: `frontend/lib/features/mv_lookup/mv_lookup_screen.dart`(新規)
- Repository: `frontend/lib/features/mv_lookup/mv_repository.dart`(新規)。`ApiClient.post('/youtube/lookup', ...)` を呼ぶ。
- ナビゲーション: `main.dart` に `NavigationBar` を置き、「MV 検索」と「チャット」を切り替える(`IndexedStack` で各画面の状態を保つ)。
  チャット画面から MV 画面を直接参照しない(feature 間の依存を作らない)。

状態(`_MvLookupScreenState`):

| 状態 | 内容 | 更新契機 |
| --- | --- | --- |
| `_loading` | 通信中か | 実行開始 / 終了 |
| `_error` | エラーメッセージ(`ApiException.detail`) | 失敗時。次の実行で消す |
| `_candidates` | 候補一覧 | MV 名で実行したとき |
| `_video` | 表示中の動画 | URL で実行したとき / 候補を選んだとき |
| `_searched` | 1 回以上実行したか | 0 件表示と初期表示を区別するため |

表示:

| 状況 | 表示 |
| --- | --- |
| 初期 | 「YouTube の URL または MV 名を入力してください」 |
| 通信中 | `LinearProgressIndicator`。実行ボタンを無効化(連打で検索クォータを消費しないため) |
| 動画 | サムネイル・曲名・アーティスト名・リンク(選択してコピーできる)・動画タイトル・チャンネル名・公開日・概要欄 |
| 分解できなかった | 「タイトルから分解できなかったため、チャンネル名と動画タイトルをそのまま表示しています」を添える |
| 候補 | サムネイル・動画タイトル・チャンネル名の一覧。タップで動画を取得 |
| 候補から選んだ動画 | ~~上部に「候補一覧に戻る」ボタン~~ → **spec 009 で変更**: 画面を切り替えず、選んだ候補の直下に展開する。同じ候補をもう一度押すと閉じる |
| 候補 0 件 | 「該当する動画が見つかりませんでした」 |
| エラー | `MaterialBanner` に `detail` を表示(チャット画面と同じ形) |

- サムネイルは `Image.network(..., webHtmlElementStrategy: WebHtmlElementStrategy.fallback)` で表示する。
  Flutter Web(CanvasKit)は CORS ヘッダの無い画像を描画できないため、その場合は `<img>` 要素で表示させる。
  読み込めない場合はアイコンを代わりに出す。
- 入力中の自動検索はしない(ボタン / Enter のときだけ実行する。検索は 1 回 100 ユニットのため)。
- `ApiException` に `detail` ゲッターを追加する。レスポンスボディの JSON から `detail` を取り出し、取り出せなければ本文をそのまま返す。
  既存の `message` は変えない(チャット画面の挙動を変えないため)。

## 6. バックエンド設計

- ルータ: `backend/app/api/routes/youtube.py`(新規)。`app/api/router.py` に登録する。
- サービス: `backend/app/services/youtube.py`(新規)。URL の解析・YouTube API の呼び出し・エラーの正規化。
- タイトル分解: `backend/app/services/mv_title.py`(新規)。外部に依存しない純粋な関数だけを置く。

### 6.1 URL の解析(`extract_video_id`)

戻り値: 動画 ID(URL だった場合)/ `None`(URL ではない = MV 名)。YouTube の動画以外の URL なら `InvalidVideoUrlError`。

- URL とみなす入力: `http://` / `https://` で始まる、またはスキーム無しで `youtube.com/`・`youtu.be/` などのホスト名から始まる。
- 対応するホスト: `youtube.com` / `www.youtube.com` / `m.youtube.com` / `music.youtube.com` / `youtu.be`

| 形式 | 動画 ID の位置 |
| --- | --- |
| `youtube.com/watch?v=<ID>` | クエリ `v`(他のパラメータ `t` / `list` / `si` などは無視) |
| `youtu.be/<ID>` | パスの 1 階層目 |
| `youtube.com/shorts/<ID>` / `/embed/<ID>` / `/live/<ID>` | パスの 2 階層目 |

- 動画 ID は `[A-Za-z0-9_-]{11}` に一致するものだけを受け付ける。
- `/playlist`・`/@<ハンドル>`・`/channel/`・`/c/`・`/user/` は「再生リスト・チャンネルの URL には対応していない」旨の `InvalidVideoUrlError`。
- `/live/<ID>` は要件に列挙していないが動画 1 本の URL なので受け付ける(AC-8 の「動画以外の URL」には当たらない)。

### 6.2 タイトルの分解(`parse_title`)

入力: 動画タイトル・チャンネル名 → 出力: `ParsedTitle(artist, song_title, parsed)`

1. **Topic チャンネル**: チャンネル名が `<アーティスト> - Topic` なら、アーティスト = `<アーティスト>`、曲名 = 装飾を除いたタイトル。
2. **装飾の除去**: 括弧 `() （） [] ［］ 【】 〔〕 〈〉 《》` のうち、中身に `Official` / `MV` / `M/V` / `PV` / `Video` / `Lyric(s)` / `Audio` / `Visualizer` / `公式` / `ミュージックビデオ` / `歌詞` を含むものを取り除く。
   末尾の `Official Music Video` / `Music Video` / `MV` / `PV` / `Official Video` / `Lyric Video` / `Official Audio` なども取り除く。
3. **パターンの照合**(上から順に最初に当てはまったもの):

   | パターン | 例 | アーティスト / 曲名 |
   | --- | --- | --- |
   | `アーティスト「曲名」` / `アーティスト『曲名』` | `YOASOBI「アイドル」` | 括弧の前 / 括弧の中。ただし「」が別の括弧の中にある場合(`YOASOBI / Idol (「アイドル」English Ver. )`)は当てはまらないものとする(実 API の確認で見つかった例) |
   | `A - B`(区切りの前後に空白。`-` `–` `—` `―` `−` `－`) | `Official髭男dism - Pretender` | A / B。ただし B だけがチャンネル名と一致するなら入れ替える |
   | `アーティスト '曲名'`(引用符 `' ‘ ’ " “ ”`) | `BTS (방탄소년단) 'Dynamite'` | 引用符の前 / 引用符の中 |
   | `A / B`(`/` の前後どちらかに空白、または全角 `／`) | `夜に駆ける / YOASOBI` | チャンネル名と一致する側がアーティスト。どちらとも言えなければ分解しない |

4. アーティスト名にも装飾の除去を適用する(例: `米津玄師 MV「Lemon」` → `米津玄師`)。
   分解後にアーティスト名か曲名が空になった場合は、そのパターンは当てはまらなかったものとする。
5. どれにも当てはまらない: アーティスト = チャンネル名、曲名 = 動画タイトル(そのまま)、`parsed = False`。

**チャンネル名との一致**: 両方を正規化(NFKC・小文字化・空白と記号の除去・`official` / `公式` / `channel` / `vevo` / `topic` の除去)したうえで、2 文字以上あり、一方がもう一方に含まれるなら一致とみなす。
例: チャンネル `Ayase / YOASOBI` → `ayaseyoasobi` に `yoasobi` が含まれる。

### 6.3 YouTube API の呼び出し(`YouTubeService`)

| メソッド | 呼ぶ API | 消費ユニット | 内容 |
| --- | --- | --- | --- |
| `lookup(query)` | — | — | 6.1 で振り分けて下の 2 つを呼ぶ |
| `get_video(video_id)` | `GET /youtube/v3/videos?part=snippet&id=<ID>` | 1 | `items` が空なら `VideoNotFoundError`。タイトルを 6.2 で分解 |
| `search(keyword)` | `GET /youtube/v3/search?part=snippet&type=video&q=<MV名>&maxResults=<件数>&regionCode=<地域>` | 100 | `id.videoId` が無い項目は捨てる |

- ベース URL は `https://www.googleapis.com`(プロトコル上の定数なのでモジュール定数にする)。
- API キーはヘッダ `X-Goog-Api-Key` で渡す(1. の方針)。キーが未設定なら API を呼ぶ前に `YouTubeApiError`。
- **search のタイトル・チャンネル名は HTML エスケープされて返る**(`&#39;` `&amp;` など)ため `html.unescape` する。videos はエスケープされない。
- サムネイルは `high` → `medium` → `default` の順で、最初にあるものを使う。
- `published_at` は ISO 8601 を `datetime` に変換する。変換できなければ `None`。
- `httpx.AsyncClient` は呼び出しごとに作る(利用頻度が低く、接続の使い回しで得るものが少ないため)。
  テスト用にコンストラクタで `transport` を差し替えられるようにする。

### 6.4 エラーの正規化

YouTube API のエラー応答 `{"error": {"code", "message", "errors": [{"reason"}], "details": [{"reason"}]}}` から判定する。

| 判定 | 条件 | 例外 |
| --- | --- | --- |
| クォータ | HTTP 429、または reason が `quotaExceeded` / `dailyLimitExceeded` / `rateLimitExceeded` / `userRateLimitExceeded` / `RATE_LIMIT_EXCEEDED` | `YouTubeQuotaError` |
| 認証 | HTTP 401 / 403、reason が `keyInvalid` / `keyExpired` / `accessNotConfigured` / `forbidden` / `ipRefererBlocked` / `API_KEY_INVALID` / `SERVICE_DISABLED` など、またはメッセージに `API key` を含む | `YouTubeAuthError` |
| 通信 | `httpx.TimeoutException` / `httpx.HTTPError`(接続失敗など) | `YouTubeNetworkError` |
| その他 | 上記以外の 200 以外の応答、JSON として読めない応答 | `YouTubeApiError` |

クォータの判定を認証より先に行う(クォータ超過も HTTP 403 で返るため)。

例外の階層:

```
YouTubeError(RuntimeError)          # この機能の業務例外の基底
├─ InvalidVideoUrlError             → 400
├─ VideoNotFoundError               → 404
├─ YouTubeQuotaError                → 503
└─ YouTubeApiError                  → 502
   ├─ YouTubeAuthError
   └─ YouTubeNetworkError
```

### 6.5 設定(`app/core/config.py` / `.env.example`)

| 設定 | 既定値 | 用途 |
| --- | --- | --- |
| `youtube_data_api_key` | 空 | YouTube Data API v3 の API キー。**秘匿情報**(`backend/.env` のみに書く) |
| `youtube_search_max_results` | `5` | MV 名で検索したときの候補数 |
| `youtube_region_code` | `JP` | 検索結果の地域(ISO 3166-1 alpha-2)。空なら指定しない |
| `youtube_request_timeout` | `10.0` | YouTube API の待ち時間の上限(秒) |

## 7. Gemini プロンプト設計

使わない(タイトルの分解はルールで行う。要件の非ゴール)。

## 8. エラーハンドリング / 非機能

- API キーをログ・エラーメッセージ・レスポンスに出さない(ヘッダで渡し、例外の文言にも含めない)。
- 失敗時は `logger.warning` で種類と HTTP ステータスだけを残す。
- リトライはしない(クォータ超過や認証エラーは再試行しても直らず、検索のリトライはクォータを余計に消費するため)。
- 1 回の実行で呼ぶ YouTube API は 1 回だけ(URL → videos、MV 名 → search)。

## 9. テスト方針

YouTube API は呼ばない。`httpx.MockTransport` でレスポンスを差し替える。

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend unit | `extract_video_id` | 各 URL 形式・余分なパラメータ・再生リスト・チャンネル・他サイト・MV 名(AC-2, AC-8) |
| backend unit | `parse_title` | AC-5 の例・Topic・スラッシュの順序判定・装飾除去・分解不可(AC-5, AC-6) |
| backend unit | `YouTubeService` | MockTransport で videos / search の正常系、0 件、`items` 空、クォータ・認証・通信エラー、キー未設定、ヘッダでキーを渡していること(AC-7, AC-9, AC-10) |
| backend api | ルータ | TestClient + `dependency_overrides` で MockTransport 付きのサービスに差し替え。ステータスコードと `detail`(AC-1, AC-3, AC-4, AC-7, AC-8, AC-10) |
| frontend | モデル | `fromJson`、`ApiException.detail` |
| frontend | 画面 | フェイク Repository で URL 入力 → 結果、MV 名 → 候補 → 選択、0 件、エラー、分解不可の注記(AC-1, AC-3, AC-4, AC-6, AC-9, AC-10) |
| 手動 | 実 API | 実キーで URL と MV 名を 1 回ずつ実行して結果を確認する(検索は 100 ユニット消費する) |
