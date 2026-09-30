# 設計: アーティストのカルチャー情報を Gemini で調べて整理する

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-29

## 0. 前提の確認結果(2026-09-29 に公式ドキュメントで確認)

| 論点 | 確認結果 | 設計への反映 |
| --- | --- | --- |
| 検索候補(Search Suggestions)の表示 | Grounding with Google Search を使う場合は**表示が必須**。応答の `searchEntryPoint.renderedContent` に HTML/CSS が入っており、それを表示する。出典は項目の近く(inline)と一覧(aggregate)の両方に示すことが求められる | 検索候補の HTML をそのまま表示する(5.3)。出典は一覧と、各セクションの出典番号の両方で示す |
| YouTube の URL を Gemini に渡す | Vertex AI でも YouTube の URL を動画入力として渡せる(プレビュー機能)。**公開動画のみ**(限定公開・非公開は不可) | 動画はダウンロードせず URL を渡す。解析できない動画は「解析できなかった」扱いにする(AC-6) |
| 映像のトークン量 | 1 秒 1 フレーム。低解像度でおよそ 100 トークン/秒(4 分の MV でおよそ 2.4 万トークン) | `media_resolution=LOW` で呼ぶ |
| 検索と構造化出力(JSON)の同時利用 | Gemini 3 以降は同じ呼び出しで使えるが、その場合 `grounding_chunks`(出典)が空になる事例が報告されている | **調べる呼び出し(検索あり・自由文)と、整理する呼び出し(検索なし・JSON)を分ける**(1.) |
| 料金 | モデルの料金とは別に、**モデルが実行した検索クエリの数だけ**課金される | 1 回の取得で検索を使う呼び出しは 1 回に限る。使い回さないため、動画を表示するたびに課金される(要件の決定事項 1) |
| 出典の形(実 API で確認) | `grounding_chunks[].web.uri` は Google のリダイレクト URL(`vertexaisearch.cloud.google.com/grounding-api-redirect/…`)で、`title` にはドメイン名が入ることがある | 画面ではタイトルとドメインが同じなら重ねて出さない |
| 所要時間(実 API で確認) | `gemini-2.5-flash` で 3 分台の MV を 1 本処理して約 50 秒。検索クエリは 6 件実行された | `culture_timeout` の既定 180 秒で足りる |

参照: [Grounding with Google Search(Vertex AI)](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/grounding/grounding-with-google-search) /
[Search Suggestions](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/multimodal/grounding-search-entry-points) /
[Grounding with Google Search(Gemini API)](https://ai.google.dev/gemini-api/docs/google-search) /
[Video understanding(Gemini API)](https://ai.google.dev/gemini-api/docs/video-understanding) /
[動画入力(Firebase AI Logic)](https://firebase.google.com/docs/vertex-ai/analyze-video) /
[構造化出力と grounding の組み合わせ(フォーラム)](https://discuss.ai.google.dev/t/grounding-metadata-grounding-chunks-grounding-supports-empty-when-using-structured-output-with-google-search-tool/113240)

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | 3 回に分けて呼ぶ: ① 検索ありで調べる(自由文)→ ② 検索なしで JSON に整理する。並行して ③ MV の映像から衣装を読み取る(JSON) | 採用 | 出典を確実に得られる(0. の報告を回避)。映像の解析だけが失敗しても Web の結果は出せる(AC-6)。①→② と ③ を並行に走らせて待ち時間を抑える |
| B | 1 回の呼び出しで検索 + 映像 + JSON 出力 | 却下 | 出典が空になるおそれがある。映像の失敗で全体が失敗する。モデルが Gemini 3 以降に限られる |
| C | ADK の `LlmAgent` + `google_search` ツール | 却下 | 呼ぶ手順が決まっているため、エージェントに判断させる必要がない。グラウンディングのメタデータ(出典・検索候補)を直接扱える `google-genai` の方が確実 |

| 案 | 画面との関係 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | フロントは `mv_lookup` 機能の中に置く(`culture_*.dart`) | 採用 | 取得の開始・入力のロックが MV 検索画面の状態と一体。別の feature にすると、動画情報(mv_lookup)とカルチャー情報の間で相互に依存してしまう(README 2.2 の「他 feature の内部への直接依存」に当たる) |
| B | `features/artist_culture/` を新設 | 却下 | 同上。後続のコーデ提案で共有が必要になったら、その spec で切り出す |

## 2. 全体フロー

```
MvLookupScreen: 動画情報が表示された(URL 入力 / 候補の選択)
  → 入力をロック(入力欄・検索ボタン・候補・「候補一覧に戻る」※)、回転ローディングを表示
    ※ spec 009 で「候補一覧に戻る」は廃止し、候補の直下に展開する形に変更した
  → CultureRepository.research(video)
  → POST /api/v1/culture/research  {"video": VideoInfo}
  → culture.py(routes): CultureRequest で検証
  → CultureService.research(video)
      ├─ (並行 1) _research_web(video)       ① 検索あり・自由文
      │     → 本文 + 出典(grounding_chunks)+ 検索候補 HTML + 検索クエリ
      │     → 本文に出典番号 [n] を差し込む(grounding_supports の segment.text を探して直後に挿入)
      │   → _structure(本文)                ② 検索なし・JSON(アーティスト特定・ファッション・経歴)
      └─ (並行 2) _analyze_video(video.url)  ③ YouTube の URL を渡す・JSON(MV の衣装)
            失敗してもここで握りつぶし、mv_outfit.status="unavailable" にする
  → CultureResponse
  → 画面にセクションごとに表示し、ロックを解除する
```

- ① と ③ は `asyncio.gather` で並行に実行し、全体に `culture_timeout` の上限をかける。
- アーティストを特定できなかった場合(`identified=false`)は、MV の衣装も表示しない(音楽と関係ない動画のため)。

## 3. API 設計

### `POST /api/v1/culture/research`

リクエスト(spec 007 の `VideoInfo` をそのまま送る):

```json
{ "video": { "video_id": "...", "url": "https://www.youtube.com/watch?v=...", "artist": "YOASOBI", "song_title": "アイドル", "title_parsed": true, "title": "...", "channel_title": "YOASOBI", "published_at": "...", "thumbnail_url": "...", "description": "..." } }
```

レスポンス (200)(値は説明用のダミー):

```json
{
  "artist": "YOASOBI",
  "identified": true,
  "message": "",
  "fashion": {
    "styles": ["ストリート", "ガーリー"],
    "colors": ["黒", "白"],
    "items": ["ベレー帽", "厚底ブーツ"],
    "worldview": "アニメーションと実写を組み合わせた…",
    "source_indices": [1, 3]
  },
  "background": {
    "summary": "…",
    "history": ["2019年 結成", "…"],
    "genres": ["J-POP"],
    "representative_songs": ["夜に駆ける", "アイドル"],
    "musical_traits": "…",
    "source_indices": [1, 2]
  },
  "mv_outfit": {
    "status": "ok",
    "message": "",
    "looks": [
      {
        "label": "メインの衣装",
        "items": [
          { "category": "ワンピース", "material": "不明", "shape": "…", "colors": ["白"], "pattern": "無地", "style": "ガーリー", "notes": "…" }
        ]
      }
    ]
  },
  "sources": [ { "index": 1, "title": "…", "url": "https://…", "domain": "…" } ],
  "search_suggestions_html": "<style>…</style><div class=\"container\">…</div>",
  "web_search_queries": ["YOASOBI ファッション", "…"],
  "model": "gemini-3.5-flash-lite"
}
```

- `identified=false` のときは `message` に理由が入り、`fashion` / `background` は空、`mv_outfit.status` は `"skipped"`(AC-8)。
- `mv_outfit.status`: `"ok"` / `"unavailable"`(映像を解析できなかった。`message` に理由)/ `"skipped"`(特定できず解析結果を使わない)。
- `source_indices` は `sources[].index`(1 始まり)を指す。範囲外の番号はサーバ側で捨てる。

エラー:

| ステータス | 条件 | 対応する例外 | ボディ |
| --- | --- | --- | --- |
| 422 | `video` の形式が不正 | (Pydantic) | FastAPI 標準 |
| 502 | Gemini の呼び出しに失敗(①② の失敗、応答を解釈できない、設定不備) | `CultureError` | `{"detail": "..."}` |
| 503 | Gemini のクォータ超過(HTTP 429 / `RESOURCE_EXHAUSTED`) | `CultureQuotaError` | `{"detail": "..."}` |
| 504 | `culture_timeout` を超えた | `CultureTimeoutError` | `{"detail": "..."}` |

③ の失敗はエラーにしない(`mv_outfit.status="unavailable"`)。

## 4. データモデル

### バックエンド: `app/schemas/culture.py`

| モデル | フィールド |
| --- | --- |
| `CultureRequest` | `video: VideoInfo`(spec 007) |
| `FashionInfo` | `styles` / `colors` / `items`(`list[str]`)、`worldview: str`、`source_indices: list[int]` |
| `BackgroundInfo` | `summary: str`、`history` / `genres` / `representative_songs`(`list[str]`)、`musical_traits: str`、`source_indices: list[int]` |
| `OutfitItem` | `category` / `material` / `shape` / `colors` / `pattern` / `style` / `notes`(spec 005 の `ClothItem` と同じ項目。後続のコーデ提案で服インデックスと同じ項目で照合するため) |
| `OutfitLook` | `label: str`、`items: list[OutfitItem]` |
| `MvOutfit` | `status: Literal["ok", "unavailable", "skipped"]`、`message: str`、`looks: list[OutfitLook]` |
| `Source` | `index: int`、`title: str`、`url: str`、`domain: str` |
| `CultureResponse` | `artist` / `identified` / `message` / `fashion` / `background` / `mv_outfit` / `sources` / `search_suggestions_html` / `web_search_queries` / `model` |

### モデルの構造化出力(`app/services/culture.py` 内のみ)

API の契約(schemas)と Gemini への指示(フィールドの description)は目的が違うため、別のモデルとして定義し、services 内で詰め替える
(README 2.2「schemas は外部 API のモデルを兼ねない」)。

| モデル | 用途 | フィールド |
| --- | --- | --- |
| `StructuredCulture` | ② の出力 | `identified: bool`、`artist: str`、`message: str`、`fashion`(`_FashionOutput`)、`background`(`_BackgroundOutput`) |
| `VideoOutfitAnalysis` | ③ の出力 | `looks: list[_LookOutput]`(`label` と spec 005 の `ClothItem` の一覧)、`summary: str` |

詰め替えのとき、「情報なし」「不明」とだけ書かれた項目は空にし、出典番号は実在するものだけを残す。

### フロントエンド: `lib/features/mv_lookup/culture_models.dart`

`CultureReport` / `FashionInfo` / `BackgroundInfo` / `MvOutfit` / `OutfitLook` / `OutfitItem` / `CultureSource` を上記と 1 対 1 で持ち、`fromJson` で組み立てる。

## 5. フロントエンド設計

- 追加ファイル(すべて `frontend/lib/features/mv_lookup/`):
  `culture_models.dart` / `culture_repository.dart` / `culture_section.dart` /
  `search_suggestions_view.dart`(+ `_web.dart` / `_stub.dart`)
- 変更: `mv_lookup_screen.dart`(取得の開始と入力のロック)

### 5.1 状態(`_MvLookupScreenState` に追加)

| 状態 | 内容 | 更新契機 |
| --- | --- | --- |
| `_cultureLoading` | カルチャー情報を取得中か | 動画情報の表示直後に true、完了 / 失敗で false |
| `_culture` | 取得結果 | 完了時。**別の動画を表示するときに消す**(AC-10) |
| `_cultureError` | 取得失敗のメッセージ | 失敗時。再試行で消す |

- 取得の開始: `_lookup()` で `_video` が設定されたら(URL 入力・候補の選択のどちらでも)`_researchCulture(video)` を呼ぶ(AC-1)。
- ロック: `_cultureLoading` の間は、入力欄(`enabled: false`)・検索ボタン・候補のタップ・「候補一覧に戻る」を無効にする(AC-2)。
  spec 009 で「候補一覧に戻る」は廃止し、ロックの対象にライブの検索を加えた(`_busy` に `_liveLoading` を含める)。
  動画情報の取得中(`_loading`)と合わせて `_busy = _loading || _cultureLoading` で判定する。
- 取得中に別タブ(チャット)へ移ることはできる。戻ったときは `IndexedStack` により状態が保たれている。

### 5.2 表示(`CultureSection`)

動画情報のカードの下に置く。

| 状況 | 表示 |
| --- | --- |
| 取得中 | `CircularProgressIndicator` と「カルチャー情報を調べています(数十秒かかることがあります)」 |
| 失敗 | エラーメッセージ(`ApiException.detail`)と「再試行」ボタン(AC-9) |
| 特定できなかった | 「アーティストを特定できませんでした」と `message`(AC-8) |
| 完了 | 調べたアーティスト名 / ファッション・ビジュアル / この MV の衣装 / 経歴・音楽性 / 出典 / 検索候補 |

- ファッションの `styles` / `colors` / `items` とジャンルは `Chip` で並べる。
- 各セクションの末尾に「出典: [1] [3]」を出し(inline)、最後に出典の一覧(番号・タイトル・ドメイン・URL)を出す(aggregate)。
- 「この MV の衣装」は `mv_outfit.status` が `unavailable` なら「映像を解析できませんでした」と `message` を出す(AC-6)。

### 5.3 検索候補(Search Suggestions)の表示

- Web: `HtmlElementView.fromTagName(tagName: 'div')` で要素を作り、`innerHTML` に `search_suggestions_html` を入れる。
  HTML は**加工しない**(Google が提供する表示をそのまま出すことが求められているため)。高さは固定(80px)で、はみ出した分は要素内でスクロールする。
- Web 以外(テスト実行環境・モバイル): HTML を描画できないため、`web_search_queries` を文字で表示する(スタブ)。
  条件付き import(`if (dart.library.js_interop)`)で切り替える。
  **モバイル向けに公開する場合は、WebView などで HTML を表示する対応が別途必要**(本 spec の対象外。README に記載)。
- 追加の依存パッケージは使わない(`dart:js_interop` / `dart:js_interop_unsafe` は SDK 付属)。

## 6. バックエンド設計

- ルータ: `backend/app/api/routes/culture.py`(新規)。`app/api/router.py` に登録する。
- サービス: `backend/app/services/culture.py`(新規)。
- スキーマ: `backend/app/schemas/culture.py`(新規)。
- Gemini のクライアントは既存の `get_media_client()`(ADC)を共有する。テストではクライアントを差し替える。

### 6.1 ① 調べる(`_research_web`)

- `client.aio.models.generate_content(model=culture_model, contents=<プロンプト>, config=GenerateContentConfig(tools=[Tool(google_search=GoogleSearch())]))`
- プロンプト(7.1)には `VideoInfo` の値を入れる。概要欄は先頭 1,500 文字まで(プロンプトが膨らむのを防ぐ)。
- 応答から取り出すもの:

| 取り出すもの | 取り出し元 |
| --- | --- |
| 本文 | `response.text` |
| 出典 | `candidates[0].grounding_metadata.grounding_chunks[].web`(`uri` / `title` / `domain`)。1 始まりの番号を振る |
| 出典番号の差し込み | `grounding_supports[]` の `segment.text` を本文から探し、直後に `[n]` を差し込む(`start_index` / `end_index` は位置の数え方(文字 / バイト)に依存するため使わず、日本語でもずれない文字列一致にする) |
| 検索候補 | `grounding_metadata.search_entry_point.rendered_content` |
| 検索クエリ | `grounding_metadata.web_search_queries` |

- 出典が 1 件も無い場合も処理は続ける(検索されなかった場合など)。その場合 `sources` は空になる。

### 6.2 ② 整理する(`_structure`)

- 検索なし・`response_schema=StructuredCulture`・`temperature=0`。入力は ① の本文(出典番号入り)と `VideoInfo` の要点。
- `source_indices` は本文中の `[n]` から、そのセクションの根拠になった番号を入れさせる。範囲外の番号は捨てる。

### 6.3 ③ MV の衣装を読み取る(`_analyze_video`)

- `contents=[Part(file_data=FileData(file_uri=<動画の URL>, mime_type="video/mp4")), Part.from_text(<指示>)]`
- `response_schema=VideoOutfitAnalysis`・`media_resolution=MEDIA_RESOLUTION_LOW`。
- 例外(非公開・年齢制限・プレビュー機能の制限など)は捕まえて `MvOutfit(status="unavailable", message=…)` にする。
- ① が失敗・タイムアウトしたら、実行中の ③ は取り消す(結果を使わない呼び出しの課金を避けるため)。

### 6.4 エラーの正規化

| 判定 | 条件 | 例外 |
| --- | --- | --- |
| クォータ | `google.genai.errors.APIError` の `code == 429` または `status == "RESOURCE_EXHAUSTED"` | `CultureQuotaError` |
| タイムアウト | 全体が `culture_timeout` 秒を超えた(`asyncio.timeout`) | `CultureTimeoutError` |
| その他 | ①② のその他の例外、`response.parsed` が期待する型でない、クライアントの設定不備 | `CultureError` |

```
CultureError(RuntimeError)       → 502
├─ CultureQuotaError             → 503
└─ CultureTimeoutError           → 504
```

### 6.5 設定(`app/core/config.py` / `.env.example`)

| 設定 | 既定値 | 用途 |
| --- | --- | --- |
| `culture_model` | `gemini-3.5-flash-lite` | ①②③ で使うモデル。Google 検索と YouTube の動画入力に対応したものを指定する |
| `culture_timeout` | `180` | ①〜③ 全体の待ち時間の上限(秒)。映像の解析を含むため長めにとる |

未決事項 2(モデル)は「`GEMINI_MODEL` とは別に `CULTURE_MODEL` を設ける」に決定する。チャット用のモデル(軽量モデルなど)が検索や動画入力に対応していない場合でも、この機能だけ別のモデルにできるため。

## 7. Gemini プロンプト設計

### 7.1 ① 調べる

- 役割: 音楽とファッションに詳しいリサーチャー。
- 入力: 動画タイトル / チャンネル名 / アーティスト名(推定値。タイトルを分解できなかった場合はチャンネル名であることを明記)/ 曲名 / 公開日 / 概要欄。
- 指示:
  1. まずこの動画のアーティストを特定する。**特定できなければ「特定できませんでした」と理由だけを書き、推測で埋めない**(AC-8)。
  2. ファッション・ビジュアル(スタイルの傾向・よく使う色・定番のアイテム・MV やアートワークの世界観)。
  3. 経歴・音楽性(概要・活動の歩み・ジャンル・代表曲・音楽的な特徴)。
  4. Web で確認できた内容だけを書き、見つからない項目は「情報なし」と書く。日本語で書く。

### 7.2 ② 整理する

- メモにない情報を足さない。「情報なし」の項目は空にする。
- 色・系統・アイテムは短く一般的な語にする(例: 「黒」「ストリート」「ブーツ」)。服インデックス(spec 005)の書き方に揃えるため。
- メモ中の `[n]` は出典番号。セクションごとに根拠になった番号を `source_indices` に入れる。

### 7.3 ③ MV の衣装

- 映像に映っている出演者の衣装を、衣装(シーン)ごとに `looks` に分けて記録する。
- 各アイテムは spec 005 の `ClothItem` と同じ基準(種類・素材・形・色・柄・系統)で書く。素材が分からなければ「不明」。
- 映像から分からないことは書かない。

## 8. エラーハンドリング / 非機能

- 待ち時間: ①→② と ③ を並行に実行する。全体の上限は `culture_timeout`(既定 180 秒)。
- 失敗時は `logger.warning` に種類と例外の型を残す(プロンプトや応答の全文はログに出さない)。
- リトライは自動では行わない(課金が増えるため)。利用者が「再試行」を押したときだけ呼び直す。
- 結果は保存しない(要件の決定事項 1)。サーバは状態を持たず、フロントも画面の状態としてだけ持つ。
- 1 回の取得で呼ぶ Gemini は 3 回(検索ありは ① の 1 回だけ)。

## 9. テスト方針

Gemini は呼ばない。`genai.Client` の代わりに、`aio.models.generate_content` だけを持つフェイクを渡す。

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend unit | 出典の取り出しと `[n]` の差し込み | グラウンディングのメタデータを組み立てて渡す(日本語の本文を含む) |
| backend unit | `CultureService.research` | フェイクのクライアントで ①②③ の正常系、特定できない場合、③ だけの失敗、①② の失敗、クォータ、タイムアウト、範囲外の出典番号 |
| backend unit | プロンプトの組み立て | 分解できなかった動画でチャンネル名である旨が入ること、概要欄を切り詰めること |
| backend api | ルータ | TestClient + `dependency_overrides`。200・422・502・503・504 |
| frontend | モデル | `CultureReport.fromJson` |
| frontend | 画面 | フェイク Repository で、動画の表示後に自動で取得が始まる / 取得中は入力できない / 完了後の表示 / 解析できなかった衣装 / 特定できない / 失敗と再試行 / 別の動画で結果が消える |
| 手動 | 実 API | 実際の MV で 1 回実行し、出典・検索候補・衣装が表示されることを確認する(検索の課金が発生する) |
