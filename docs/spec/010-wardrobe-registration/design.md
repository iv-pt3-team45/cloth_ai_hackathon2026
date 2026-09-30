# 設計: 手持ちの服の写真を登録する

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-30

## 1. 設計方針

| 案 | 登録の流れ | 採否 | 理由 |
| --- | --- | --- | --- |
| A | 「解析(保存しない)」と「保存」を別の API にする。写真は 1 枚ずつ送る | 採用 | 保存前の確認・修正(AC-4)と、取りやめたら何も残らない(AC-7)を素直に満たす。1 枚ずつなので写真ごとのエラー(AC-11 / 12)と進み具合(AC-2)も自然に扱える |
| B | 解析と同時に仮保存し、確定で本保存 | 却下 | 取りやめたときの仮保存の後始末が要る |
| C | 全部の写真を 1 回の API で送る | 却下 | 10 枚 × 10 MB を base64 にすると 1 リクエストが 130 MB 超になる |

| 案 | 属性の型 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | spec 005 の `ClothItem` に「季節・暖かさ・使う場面」を**既定値つきで追加**して共有する | 採用 | 服の属性の定義を 1 か所に保てる。既存の `index.json`(項目が無い)も既定値で読める。006 のエージェントの検索にも新しい項目が効く |
| B | 登録用に別の型を作る | 却下 | 005 の CLI・006 のツールと形式が分かれ、同じ `index.json` を読めなくなる |

| 案 | 保存 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | 保存処理を `WardrobeStore`(Protocol)で抽象化し、今はローカルファイルの実装だけを作る | 採用 | 将来 Cloud(Storage / Firestore)に移すとき、実装を差し替えるだけで済む(要件のゴール) |

画像の受け渡しは、チャットの添付(`app/schemas/chat.py` の `Attachment`)と同じ **base64 の JSON** にする(バックエンドに依存を足さない)。
フロントで写真を選ぶためのパッケージは **`image_picker`**(Flutter 公式。Web と iOS / Android のカメラ・写真に対応)を追加する(要件の決定事項 3)。

## 2. 全体フロー

```
WardrobeScreen(一覧) ─ [写真を追加] → PhotoPicker(image_picker)で最大 10 枚を選ぶ
  → WardrobeReviewScreen(確認画面。保存するまで何も残らない)
      ├─ 1 枚ずつ順に: POST /api/v1/wardrobe/analyze  {image}
      │     → WardrobeService.analyze → analyze_cloth_bytes()(spec 005 の解析を画像データでも使えるようにしたもの)
      │     → 服ごとの属性(季節・暖かさ・使う場面は選択肢に整える)
      ├─ 利用者が属性を直す / 写真・服を外す
      └─ [保存] 写真ごとに: POST /api/v1/wardrobe/items  {image, items, summary}
            → WardrobeService.register → LocalWardrobeStore.add()
               ├─ data/wardrobe/images/<ファイル名>   … 写真
               └─ data/wardrobe/index.json            … spec 005 形式 + 服ごとの id
  → 一覧に戻って再読み込み: GET /api/v1/wardrobe/items
  → 削除: DELETE /api/v1/wardrobe/items/{id}

チャットのエージェント(spec 006)は CLOTH_INDEX_PATH(既定を data/wardrobe/index.json に変更)を読むため、
登録・削除はそのまま参照に反映される(ツールは呼ばれるたびにファイルを読む)。
```

## 3. API 設計

| メソッド / パス | 内容 | 成功 |
| --- | --- | --- |
| `POST /api/v1/wardrobe/analyze` | 写真 1 枚を解析する(**保存しない**) | 200 `AnalyzeResponse` |
| `POST /api/v1/wardrobe/items` | 写真 1 枚と、確定した服の属性を保存する | 201 `RegisterResponse` |
| `GET /api/v1/wardrobe/items` | 登録済みの服の一覧(新しい順) | 200 `WardrobeListResponse` |
| `DELETE /api/v1/wardrobe/items/{item_id}` | 服 1 点を削除する。写真に服が残らなければ写真も消す | 204 |
| `GET /api/v1/wardrobe/images/{image}` | 保存した写真 | 200(画像) |

リクエストの例(値は説明用のダミー):

```json
// POST /api/v1/wardrobe/analyze
{ "image": { "mime_type": "image/jpeg", "data": "<base64>" } }

// POST /api/v1/wardrobe/items
{
  "image": { "mime_type": "image/jpeg", "data": "<base64>" },
  "items": [
    {
      "category": "Tシャツ", "material": "綿", "shape": "半袖クルーネック", "colors": ["白"],
      "pattern": "無地", "style": "カジュアル", "notes": "",
      "seasons": ["春", "夏"], "warmth": "薄手", "occasions": ["普段着", "ライブ・フェス"]
    }
  ],
  "summary": "白い無地の T シャツ"
}
```

`GET /api/v1/wardrobe/items` の応答の要素は、上の属性に `id`(服ごと)・`image`(写真のファイル名)・`registered_at` を足したもの。

エラー:

| ステータス | 条件 | 例外 |
| --- | --- | --- |
| 400 | base64 が不正、中身が指定の形式の画像ではない | `WardrobeInputError` |
| 404 | 削除する服 / 写真が無い | `WardrobeNotFoundError` |
| 413 | 写真が `WARDROBE_MAX_IMAGE_BYTES`(10 MB)を超える | `WardrobeImageTooLargeError` |
| 422 | `mime_type` が jpeg / png / webp 以外、項目が選択肢の外、登録する服が 0 件・種類が空など(Pydantic) | — |
| 502 | Gemini の解析に失敗 | `WardrobeError` |
| 503 | Gemini のクォータ超過 | `WardrobeQuotaError` |

- 服が写っていない写真は、解析が 200・`items: []` を返す。フロントがその写真をエラーとして扱う(AC-11)。
- 写真のファイル名は `^[A-Za-z0-9._-]+$` だけを受け付け、保存先のフォルダの外を指せないようにする。

## 4. データモデル

### 4.1 属性(`app/services/cloth_index.py` の `ClothItem` に追加)

| フィールド | 型 | 値 |
| --- | --- | --- |
| `seasons` | `list[str]`(既定 `[]`) | 春 / 夏 / 秋 / 冬(複数) |
| `warmth` | `str`(既定 `""`) | 薄手 / 普通 / 厚手(1 つ。分からなければ空) |
| `occasions` | `list[str]`(既定 `[]`) | 普段着 / きれいめ / フォーマル / スポーツ・アウトドア / ライブ・フェス(複数) |

- 「きれいめ」は、指示と画面では「きれいめ(食事・オフィス)」と説明し、値は「きれいめ」で保存する。
- Gemini の構造化出力では文字列で受け、**`normalize_item()` で選択肢の外の値を捨てる**(想定外の値で応答全体の解釈が失敗しないように。spec 009 と同じ考え方)。
  「きれいめ(食事・オフィス)」のような説明つきの値は「きれいめ」に直す。
- 選択肢は `app/schemas/wardrobe.py` の `Literal`(`Season` / `Warmth` / `Occasion`)を正とし、services はそこから取り出す。
- 既定値があるため、項目の無い既存の `index.json`(spec 005 のサンプル)もそのまま読める。
- 影響: spec 005 の CLI の出力にも新しい項目が入る。006 の検索(`item_text`)の対象にも加える。
  008 の MV の衣装解析(`_LookOutput`)も `ClothItem` を使うが、API の `OutfitItem` は新しい項目を持たないため応答は変わらない。

### 4.2 API のスキーマ(`app/schemas/wardrobe.py`)

| モデル | フィールド |
| --- | --- |
| `WardrobeImage` | `mime_type: Literal["image/jpeg", "image/png", "image/webp"]`、`data: str`(base64) |
| `ClothAttributes` | 種類・素材・形・色・柄・系統・特徴、`seasons: list[Season]`、`warmth: Warmth \| None`、`occasions: list[Occasion]` |
| `AnalyzeRequest` / `AnalyzeResponse` | `image` / `items: list[ClothAttributes]`・`summary`・`model` |
| `RegisterRequest` | `image`、`items: list[ClothAttributes]`(1〜20 件、種類は必須)、`summary` |
| `RegisteredCloth` | `ClothAttributes` + `id`・`image`・`registered_at` |
| `RegisterResponse` / `WardrobeListResponse` | `items: list[RegisteredCloth]`(一覧は `count` も) |

`warmth` は API では `None`、保存(`ClothItem`)では空文字で「分からない」を表す。

### 4.3 保存形式(`data/wardrobe/index.json`)

spec 005 の形式に、服ごとの `id` を足したもの。005 の `load_index` と 006 の `load_wardrobe` は `id` を無視して読める。

```json
{
  "generated_at": "2026-09-30T10:00:00+09:00",
  "model": "gemini-3.5-flash-lite",
  "source_dir": "app",
  "count": 1,
  "entries": [
    {
      "image": "cloth-20260930-100000-a1b2c3.jpg",
      "items": [ { "id": "3f9c0d2e1a7b", "category": "Tシャツ", "...": "...", "seasons": ["春"], "warmth": "薄手", "occasions": ["普段着"] } ],
      "summary": "白い無地の T シャツ",
      "model": "gemini-3.5-flash-lite",
      "analyzed_at": "2026-09-30T10:00:00+09:00"
    }
  ]
}
```

- `id` の無い服(spec 005 の CLI で作った index など)は、読み込み時に `<写真のファイル名>#<番号>` を割り当てる(削除できるように)。
- 書き込みは一時ファイルに書いてから置き換える(途中で落ちても `index.json` が壊れないように)。読み書きはロックで直列にする。

## 5. フロントエンド設計

- 新しい feature: `frontend/lib/features/wardrobe/`

| ファイル | 役割 |
| --- | --- |
| `wardrobe_models.dart` | `ClothAttributes` / `RegisteredCloth` / `ClothAnalysis` / 選択肢の定数 |
| `wardrobe_repository.dart` | API 呼び出し(解析・保存・一覧・削除・写真の URL) |
| `photo_picker.dart` | `PhotoPicker`(写真を選ぶ抽象)と `image_picker` を使う実装。テストではフェイクに差し替える |
| `wardrobe_screen.dart` | 一覧・削除・「写真を追加」 |
| `wardrobe_review_screen.dart` | 解析・確認・修正・保存 |

- `main.dart` の `NavigationBar` に「手持ちの服」(`Icons.checkroom`)を追加する。並びは「MV 検索 / 手持ちの服 / チャット」(AC-1)。
- `core/api_client.dart` に `delete()` を追加する(204 の空の本文も扱う)。

### 5.1 一覧(`WardrobeScreen`)

| 状況 | 表示 |
| --- | --- |
| 読み込み中 | `CircularProgressIndicator` |
| 0 件 | 「まだ服が登録されていません。右下の「写真を追加」から登録してください」(AC-8) |
| 1 件以上 | 写真(サーバの写真の URL)・種類・色・系統・季節・暖かさ・使う場面のカード。削除ボタン(確認ダイアログあり)(AC-9) |
| 失敗 | エラーと「再読み込み」 |

### 5.2 写真を選ぶ(`PhotoPicker`)

- `ImagePicker().pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85)` で選ぶ(縮小して送る量を減らす)。
- **1 回に 10 枚まで**(未決事項 2 の案を採用)。11 枚以上選んだら先頭 10 枚を使い、その旨を出す。
- 形式は `mimeType` か拡張子で判定する。jpeg / png / webp 以外は API を呼ばずにその写真をエラーにする(AC-11)。

### 5.3 確認画面(`WardrobeReviewScreen`)

- 開いたら 1 枚ずつ順に解析する。上部に「解析中 2 / 5」と `LinearProgressIndicator`(AC-2)。
- 写真ごとのカード: 写真(`Image.memory`)・状態(解析待ち / 解析中 / 完了 / エラー)・「この写真を登録する」スイッチ。
  - エラー(Gemini の失敗・服が写っていない・形式・サイズ)は理由と「再解析」ボタン(形式エラーは再解析なし)(AC-11 / 12)。
- 服ごとの編集欄(AC-3 / 4): 「登録する」チェック、種類・色(「、」区切り)・素材・形・柄・系統・特徴の入力欄、
  季節(`FilterChip`・複数)・暖かさ(`ChoiceChip`・1 つ。もう一度押すと解除)・使う場面(`FilterChip`・複数)。
- 「保存」: 解析中は押せない。登録する服が 1 件も無ければ押せない。写真ごとに順に保存し、成功したら一覧に戻る(AC-5 / 6)。
  途中で失敗したら、保存できた写真は確認画面から外し、残りとエラーを表示する。
- 「キャンセル」/ 戻る: 確認ダイアログのうえ、何も保存せずに一覧へ戻る(AC-7)。

## 6. バックエンド設計

| ファイル | 内容 |
| --- | --- |
| `app/services/cloth_index.py`(変更) | `ClothItem` に 3 項目を追加。`analyze_cloth_bytes(data, mime_type, ...)` を追加し、既存の `analyze_cloth_image(path)` はこれを呼ぶ。`normalize_item()` を追加。指示文に 3 項目の説明を追加 |
| `app/services/wardrobe_store.py`(新規) | `WardrobeStore`(Protocol)と `LocalWardrobeStore`(`index.json` と `images/` を扱う) |
| `app/services/wardrobe_registry.py`(新規) | `WardrobeService`: 画像の検証(base64・サイズ・先頭のバイトで形式を確認)、解析、保存、一覧、削除、写真の読み出し。業務例外への変換 |
| `app/services/wardrobe.py`(変更) | 検索の対象に 3 項目を追加。インデックスが無いときの案内に「手持ちの服」タブからの登録を加える |
| `app/schemas/wardrobe.py`(新規) | 4.2 のスキーマと選択肢の `Literal` |
| `app/api/routes/wardrobe.py`(新規) | 3. のエンドポイント。`app/api/router.py` に登録する |

- ハンドラは同期関数(`def`)にする。解析は spec 005 の同期の呼び出しを再利用し、FastAPI のスレッドプールで動かす。
- Gemini のクォータ超過は `grounding.is_quota_error()` で判定する(spec 008 / 009 と共通)。
- 画像の形式の確認: JPEG は `FF D8 FF`、PNG は `89 50 4E 47 0D 0A 1A 0A`、WebP は `RIFF....WEBP` で始まること。
- 写真のファイル名は `media.build_file_name("cloth", mime_type, ".jpg")`(日時 + 乱数)を使う。服の `id` は乱数 12 桁。

### 6.1 設定

| 設定 | 既定値 | 用途 |
| --- | --- | --- |
| `cloth_index_path` | **`data/wardrobe/index.json`(変更。旧: `tests/sample_cloth_indexs/index.json`)** | 登録した服のインデックス。006 のエージェントも読む。写真は同じフォルダの `images/` |
| `wardrobe_max_image_bytes` | `10485760`(10 MB) | 写真 1 枚の上限 |
| `cloth_index_model` | (既存) | 解析に使うモデル |

- `backend/data/` は Git 管理外にする(`.gitignore`)。Docker Compose ではホストの `backend/` がマウントされるため、再起動しても残る。
- 既存のサンプル(`tests/sample_cloth_indexs`)は取り込まない(要件の決定事項 2)。CLI の既定の入出力先もそのまま。
  CLI(`run_agent.py` など)でサンプルを参照したいときは `--index tests/sample_cloth_indexs/index.json` を付ける。

## 7. Gemini プロンプト設計

spec 005 の指示文(`_INSTRUCTION`)に次を足す。

- seasons は「春」「夏」「秋」「冬」から、着るのに向いている季節をすべて選ぶこと。
- warmth は「薄手」「普通」「厚手」から 1 つ選ぶこと。
- occasions は「普段着」「きれいめ(食事・オフィス)」「フォーマル」「スポーツ・アウトドア」「ライブ・フェス」から、向いている場面をすべて選ぶこと。

## 8. エラーハンドリング / 非機能

- 解析は写真 1 枚につき Gemini 1 回。フロントが 1 枚ずつ順に呼ぶため、同時に複数は呼ばない(クォータの瞬間的な消費を避ける)。
- 写真とインデックスはローカルにだけ保存し、ログには写真の中身を出さない。
- 自動のリトライはしない(再解析は利用者が押したときだけ)。

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend unit | `normalize_item` / `analyze_cloth_bytes` | 選択肢の外の値・説明つきの値。フェイクのクライアント(同期)で入力の組み立てと結果の整え方 |
| backend unit | `LocalWardrobeStore` | 一時フォルダで追加・一覧・削除、最後の服を消すと写真も消える、`id` の無い既存形式を読める、005 の `load_index` / 006 の `load_wardrobe` で読める |
| backend unit | `WardrobeService` | base64 不正・サイズ超過・形式の不一致・服 0 件・クォータ・Gemini の失敗 |
| backend api | ルータ | 200 / 201 / 204 / 400 / 404 / 413 / 422 / 502 / 503、写真の取得とファイル名の検証 |
| backend unit | 006 との連携 | 登録した服を `list_wardrobe` が返す(AC-10) |
| frontend | モデル / 画面 | フェイクの Repository と PhotoPicker で: タブ、一覧・0 件・削除、解析の進み具合、複数の服、修正、除外、保存、取りやめ、写真ごとのエラーと再解析 |
| 手動 | 実 API | 実際の服の写真 1 枚で解析 → 保存 → 一覧 → チャットで参照 → 削除 |
