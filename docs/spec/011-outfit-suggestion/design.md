# 設計: 情報の確認タブと、手持ちの服からのコーデ提案

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-10-02

## 1. 設計方針

| 案 | タブをまたぐ状態の共有 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | MV 検索タブが状態の要約(`MvLookupSnapshot`)をコールバックで外へ出し、`main.dart`(アプリの組み立て)が `ValueNotifier` で確認タブへ渡す | 採用 | 依存パッケージを足さない。feature どうしが互いの画面の内部に依存しない(README 2.2)。MV 検索タブの状態の持ち方は変えずに済む |
| B | 状態管理パッケージ(provider / riverpod)を入れる | 却下 | 依存の追加になり、この規模では得るものが少ない |
| C | MV 検索タブの状態をバックエンドに保存し、確認タブが読み直す | 却下 | カルチャー情報・ライブ情報(グラウンディング結果)を保存しない方針(spec 008 / 009)に反する |

| 案 | 提案と画像の API | 採否 | 理由 |
| --- | --- | --- | --- |
| A | 「提案」と「画像の生成」を別の API にし、フロントが続けて呼ぶ | 採用 | 提案を先に表示できる。画像の生成だけの失敗・再生成(AC-13)を素直に扱える |
| B | 1 回の API で両方を返す | 却下 | 画像の生成(数十秒)が終わるまで提案も見られない |

| 案 | 手持ちの服の渡し方 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | 手持ちの服はバックエンドが保存先(spec 010)から読む。フロントは MV・カルチャー・ライブだけを送る | 採用 | 提案に使う服の正がサーバ側にあり、「手持ち以外の服を含めない」をサーバで確かめられる(AC-10) |

## 2. 全体フロー

```
MvLookupScreen ──(状態が変わるたびに)── onChanged(MvLookupSnapshot)
                                          │
HomeShell(main.dart) ── ValueNotifier<MvLookupSnapshot> ──→ ConfirmScreen(確認タブ)
                                                              ├─ 入力 / MV / アーティスト / カルチャー / ライブと天気
                                                              ├─ 手持ちの服の横並び(WardrobeRepository.list)
                                                              └─ [コーデを提案]
                                                                   ① POST /api/v1/outfit/suggest {video, culture, live}
                                                                        → OutfitService.suggest
                                                                           ├─ 手持ちの服を保存先から読む(spec 010)
                                                                           ├─ Gemini(OUTFIT_MODEL・構造化出力)で 1 コーデ
                                                                           └─ 手持ちに無い服の id を捨てる
                                                                   ② POST /api/v1/outfit/image {item_ids, title}
                                                                        → OutfitService.generate_image
                                                                           ├─ マネキン画像 + 服の写真(保存先から)
                                                                           ├─ Nano Banana 2 Flash Lite(IMAGE_MODEL)
                                                                           └─ 生成画像を created_images/ に保存し、base64 でも返す
```

## 3. API 設計

### `POST /api/v1/outfit/suggest`

リクエスト(画面が持っている内容をそのまま送る。値は説明用のダミー):

```json
{
  "video": { "...": "spec 007 の VideoInfo" },
  "culture": { "...": "spec 008 の CultureResponse(取得できていなければ null)" },
  "live": { "...": "spec 009 の LiveCandidate(選んだ 1 件)" },
  "venue_format": "standing"
}
```

- `venue_format`(任意。2026-10-05 追加): ライブを選んだ時点で調べた会場の形態(spec 014。`standing` / `seated` / `mixed` / `unknown`)。
  送られてきたら(`unknown` でも)サーバはもう一度調べない。省略したときだけ、提案の前に調べる。

レスポンス (200):

```json
{
  "title": "ポップに映えるライブ参戦コーデ",
  "summary": "…",
  "points": ["当日は晴れで最高 27℃のため薄手で", "…"],
  "items": [
    { "id": "3f9c0d2e1a7b", "image": "cloth-….jpg", "category": "Tシャツ", "...": "spec 010 の属性", "role": "トップス", "reason": "…" }
  ],
  "excluded_count": 0,
  "model": "gemini-3.5-flash-lite"
}
```

- `items` は**手持ちの服だけ**。Gemini が手持ちに無い id を返したら捨て、その数を `excluded_count` に入れる(AC-10)。
- 手持ちの服が 0 件なら 400。手持ちの服を 1 点も使えなかったら 502。

### `POST /api/v1/outfit/image`

リクエスト: `{ "item_ids": ["3f9c0d2e1a7b", "…"], "title": "…" }`(1〜10 件)

レスポンス (200): `{ "mime_type": "image/png", "data": "<base64>", "file_name": "outfit-….png", "model": "gemini-3.1-flash-lite-image" }`

- 服の写真はバックエンドが保存先から読む。手持ちに無い id があれば 400。
- 生成した画像は spec 003 と同じ `created_images/` に保存し、画面に出すために base64 でも返す。

エラー(2 つの API で共通):

| ステータス | 条件 | 例外 |
| --- | --- | --- |
| 400 | 手持ちの服が 0 件、手持ちに無い id を指定 | `OutfitInputError` |
| 422 | 入力の形式が不正(Pydantic) | — |
| 502 | Gemini の失敗、応答を解釈できない、手持ちの服を 1 点も使えなかった、モデルが画像を返さない、マネキン画像が無い | `OutfitError` |
| 503 | Gemini のクォータ超過 | `OutfitQuotaError` |
| 504 | 待ち時間の上限を超えた | `OutfitTimeoutError` |

## 4. データモデル

### バックエンド: `app/schemas/outfit.py`

| モデル | フィールド |
| --- | --- |
| `OutfitSuggestRequest` | `video: VideoInfo`(007)、`culture: CultureResponse \| None`(008)、`live: LiveCandidate`(009) |
| `SuggestedCloth` | spec 010 の `RegisteredCloth` + `role`(トップス / ボトムスなど)・`reason` |
| `OutfitSuggestion` | `title` / `summary` / `points: list[str]` / `items: list[SuggestedCloth]` / `excluded_count` / `model` |
| `OutfitImageRequest` | `item_ids: list[str]`(1〜10)、`title` |
| `OutfitImageResponse` | `mime_type` / `data`(base64)/ `file_name` / `model` |

構造化出力(`app/services/outfit.py` 内のみ): `_OutfitOutput { title, summary, points, items: [{ id, role, reason }] }`。

### フロントエンド

| ファイル | 内容 |
| --- | --- |
| `features/mv_lookup/mv_lookup_snapshot.dart` | `MvLookupSnapshot`: 入力した MV 名 / URL、表示中の動画、カルチャー情報(取得中か)、ライブ検索の条件、選んだライブ |
| `features/outfit/outfit_models.dart` | `OutfitSuggestion` / `SuggestedCloth` / `OutfitImage` |

## 5. フロントエンド設計

### 5.1 タブと状態の受け渡し

- `main.dart` の並びを「MV 検索 / 手持ちの服 / **確認** / チャット」にする(AC-1)。
- `MvLookupScreen` に `onChanged: ValueChanged<MvLookupSnapshot>?` を足す。状態を変えるたび(`setState` の後)に要約を出す。
- `HomeShell` が `ValueNotifier<MvLookupSnapshot>` に入れ、`ConfirmScreen` は `ValueListenableBuilder` で表示する(AC-7)。
- `ConfirmScreen` には `active`(確認タブが表示中か)を渡し、表示されたときに手持ちの服を読み直す(服の登録・削除を反映。AC-7)。
- 依存の向き: `outfit` feature は `mv_lookup` / `wardrobe` の**公開しているモデル・Repository・部品**(`MvLookupSnapshot`・`WardrobeRepository`・`GroundingFooter` など)だけを使い、画面の内部には依存しない。

### 5.2 確認タブ(`features/outfit/confirm_screen.dart`)

| 欄 | 表示 | 無いとき |
| --- | --- | --- |
| 入力 | MV: 入力した MV 名 / URL。ライブ: 条件(ライブ情報・日付) | 「まだありません(MV 検索タブで入力してください)」 |
| MV 情報 | サムネイル・曲名・アーティスト名・リンク | 同上 |
| アーティスト情報 | カルチャー情報で特定した名前(無ければ動画の名前)と概要 | 「カルチャー情報を取得中です」など |
| カルチャー情報 | ファッション・ビジュアル(スタイル・色・アイテム・世界観)、この MV の衣装、音楽ジャンル | 同上 |
| ライブ情報 | 選んだライブのライブ名・場所・日付・天気・客席(spec 014。「客席: スタンディング(立ち見)」「着席(座席あり)」「スタンディングと着席の両方あり(チケットによって異なる)」「不明」、調べている間は「調べています…」) | 「まだありません(MV 検索タブの「ライブを探す」で選んでください)」 |
| 手持ちの服 | 小さな写真の横並び(5.3) | 「まだありません(手持ちの服タブで登録してください)」 |
| コーデ提案 | ボタン・足りないもの・提案・画像(5.4) | — |

- カルチャー情報とライブ情報は Google 検索のグラウンディング結果のため、spec 008 / 009 と同じく**出典と検索候補**(`GroundingFooter`)を添える(利用条件)。

### 5.3 手持ちの服の横並び(`features/outfit/wardrobe_strip.dart`)

- `LayoutBuilder` で幅を取り、**1 画面に並ぶ枚数**を決める(未決事項 2 の決定):

| 幅 | 枚数 |
| --- | --- |
| 600 未満(スマホ) | 4 |
| 600 以上 1024 未満(タブレット) | 6 |
| 1024 以上(PC) | 8 |

- 1 枚の幅 = (幅 − 間隔の合計) ÷ 枚数。横向きの `ListView` で、はみ出た分は横にスクロールして見る(AC-5)。
- 写真の下に種類を 1 行で出す。提案に使った服を並べるときも同じ部品を使い、理由を添える。

### 5.4 コーデ提案

- 押せる条件: 手持ちの服 1 点以上・表示中の動画・選んだライブがそろい、カルチャー情報の取得中でなく、提案・生成中でもないこと。
  足りないときは「足りないもの: 手持ちの服 / MV / ライブの選択」を出す(AC-8)。
- 押すと ① 提案 → ② 画像の生成 を続けて行う。それぞれの間はローディングを出し、ボタンを押せなくする(AC-12)。
- 提案: タイトル・説明・使う服(写真の横並び + 役割と理由)・ポイント。手持ちに無い服を除いた場合はその旨を小さく出す。
- 画像: `Image.memory` で表示する。生成だけ失敗したら、提案は残して画像の欄にエラーと「画像を作り直す」(AC-13)。
- もう一度押すと、提案も画像も消してからやり直す(AC-14)。

## 6. バックエンド設計

| ファイル | 内容 |
| --- | --- |
| `app/services/outfit.py`(新規) | `OutfitService`: 手持ちの服の読み込み・プロンプトの組み立て・提案(構造化出力)・手持ち以外の除外・画像の生成と保存。業務例外への変換 |
| `app/schemas/outfit.py`(新規) | 4. のスキーマ |
| `app/api/routes/outfit.py`(新規) | 3. のエンドポイント。`app/api/router.py` に登録する |
| `app/assets/white_manekin.jpeg`(移動) | `app/created_images/`(Git 管理外)から移して Git で管理する |

- 手持ちの服は spec 010 の `LocalWardrobeStore`(`CLOTH_INDEX_PATH`)から読み、`wardrobe_registry.to_registered()` で API の形にする。
- Gemini のクライアントは既存の `get_media_client()`、クォータの判定は `grounding.is_quota_error()`、自動関数呼び出しの無効化は `grounding.NO_AFC`。
- 生成画像の保存は `media.build_file_name("outfit", …)` と `media.save_media()`(spec 003 と同じ)。

### 6.1 ① 提案のプロンプト

- 役割: プロのスタイリスト。
- 入力(テキスト): 手持ちの服の一覧(`id` と属性すべて)、MV(曲名・アーティスト・動画タイトル)、
  カルチャー情報(ファッション・ビジュアル、この MV の衣装、音楽ジャンル、概要)、ライブ(ライブ名・会場・所在地・日付)、天気(実績 / 予報・概況・気温・降水確率。無ければ「不明」)、会場の形態(スタンディング / 着席。分からなければ行ごと書かない)。
- 会場の形態(2026-10-02 追加、2026-10-05 更新): 画面が `venue_format` を送ってきたらそれを使う。送られてこなかったときだけ、提案の呼び出しの前に spec 014 の `lookup_venue_info` でライブの会場名・所在地・ライブ名・公演日を渡して調べる。
  `get_venue_info` は同期関数なので `asyncio.to_thread` で別スレッドで動かす(イベントループを止めないため)。
  待ち時間の上限は `venue_info_timeout`(既定 30 秒)。失敗・時間切れ・形態不明のときは形態なしで提案を続ける(提案全体は止めない)。
- 指示:
  - 使う服は手持ちの一覧にある服だけ。`id` で指定する。一覧に無い服(買い足す服・小物)は出さない。
  - トップスとボトムス(またはワンピース)を基本に、必要なら上着・靴・小物を手持ちから足す。同じ役割の服を重ねない。
  - 天気・気温と、服の季節・暖かさを合わせる。会場が屋内か屋外かも考える。
  - 会場の形態が書かれていれば合わせる(スタンディングなら動きやすさ・歩きやすい靴・荷物になる厚手の上着を避ける、着席なら座っても窮屈でない服・後ろの視界をさえぎる大きな帽子を避ける、混在なら立っても座っても困らない脱ぎ着しやすい服)。
  - アーティストのファッションの傾向や MV の衣装の雰囲気を取り入れ、ライブの場面(使う場面「ライブ・フェス」を優先)に合わせる。
  - 理由は具体的に書く。
- `response_schema=_OutfitOutput`・`temperature` は 0.7(提案に幅を持たせる)。

### 6.2 ② 画像の生成

- 入力: **1 枚目にマネキン画像**、続けて**提案に使う服の写真**(同じ写真は 1 回だけ)、最後に指示文。
- 指示文は写真の番号と、その写真のどの服を使うか(種類と色だけ。1 枚の写真に複数の服が写っていることがあるため)を伝える。
  服の見た目は**写真から再現させる**(属性の文字から作らせない)。
- 指示: マネキンに指定の服をそのまま着せる。写真の色・柄・形・プリントを忠実に再現する。写真に無い服や小物を足さない。
  マネキンの姿勢・台・背景・画角はそのまま保つ。
- `response_modalities=["TEXT", "IMAGE"]`(spec 003 の画像生成と同じ)。応答の最初の画像を使う。

### 6.3 設定

| 設定 | 既定値 | 用途 |
| --- | --- | --- |
| `outfit_model` | `gemini-3.5-flash-lite` | 提案に使うモデル(未決事項 1 の決定: `GEMINI_MODEL` とは別に設ける) |
| `outfit_timeout` | `120` | 提案の待ち時間の上限(秒) |
| `outfit_mannequin_path` | `app/assets/white_manekin.jpeg` | マネキン画像(backend/ からの相対) |
| `venue_info_timeout` | `30` | 提案の前に会場の形態(spec 014)を調べる待ち時間の上限(秒)。超えたら形態なしで提案する |
| `image_model` / `media_generation_timeout` | (既存) | 画像の生成に使うモデルと、待ち時間の上限 |

## 7. エラーハンドリング / 非機能

- 提案・画像ともに自動のリトライはしない(利用者が押したときだけ)。
- マネキン画像が無い場合は、画像の生成だけを 502 にする(提案はできる)。
- ログには例外の型だけを残す(プロンプトや画像の中身は出さない)。
  画像が返らなかったときは、原因を追えるよう応答の終了理由(`finish_reason`)だけを残す
  (T-08 で、同じ入力でも時々画像が返らないことを確認した。再試行で返る)。
- カルチャー情報・ライブ情報はリクエストで受け取るだけで保存しない(spec 008 / 009 の方針)。

## 8. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend unit | プロンプトの組み立て | 手持ちの服の id と属性・MV・カルチャー・ライブ・天気(不明を含む)が入る。会場の形態が入る / 不明なら入らない |
| backend unit | 会場の形態 | ライブの情報を F14 に渡す、失敗・時間切れでも提案する、会場名が無ければ呼ばない |
| backend unit | 提案 | フェイクのクライアントで: 手持ちに無い id の除外と件数、重複の除外、手持ち 0 件、1 点も使えない、解釈できない、クォータ、タイムアウト |
| backend unit | 画像 | マネキンが 1 枚目・同じ写真は 1 回・指示文に写真の番号と服、画像の取り出しと保存、手持ちに無い id、マネキンが無い、画像が返らない |
| backend api | ルータ | 200 / 400 / 422 / 502 / 503 / 504 |
| frontend | モデル | `fromJson` |
| frontend | `MvLookupScreen` | 動画の表示・ライブの選択で `onChanged` に要約が出る |
| frontend | 確認タブ | 各欄の表示と「まだありません」、横並びの枚数(幅ごと)、押せる条件、提案 → 画像、画像だけの失敗と作り直し、押し直し |
| 手動 | 実 API | 実際の手持ちの服・MV・ライブで 1 回提案し、マネキンに着せた画像を目で確かめる |
