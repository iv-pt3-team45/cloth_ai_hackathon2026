# 設計: 手持ちの服の Cloud Storage への保存(F06)

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-10-08

## 1. 設計方針

既存の `WardrobeStore`(Protocol。`app/services/wardrobe_store.py`)に、Cloud Storage の実装 `GcsWardrobeStore` を足す。
保存先を使う 3 か所(登録・コーデ提案・エージェントのツール)は、`LocalWardrobeStore` を直接作るのをやめて、
設定から保存先を選ぶ関数 `create_wardrobe_store(settings)` を通す。

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | `WardrobeStore` の実装を足し、設定(`WARDROBE_STORAGE`)で切り替える。写真と `index.json` の両方をバケットに置く | 採用 | 抽象化が既にあり、呼び出し側の変更が最小。`index.json` の形式をローカルと揃えられる。既定をローカルにすれば既存の動きは変わらない |
| B | 写真だけバケット、`index.json` はローカル | 却下 | 再起動で一覧が消え、写真だけが残る(要件の決定) |
| C | 属性を Firestore、写真を Cloud Storage | 却下 | 要件の非ゴール。ログイン機能の spec で改めて検討する |
| D | Cloud Storage FUSE でバケットを Cloud Run にマウントし、`LocalWardrobeStore` をそのまま使う | 却下 | ローカル開発では使えない(Windows)。同時書き込みの保証が無く、AC-7 を満たせない |

## 2. 全体フロー

```
routes/wardrobe.py ─→ WardrobeService ─┐
routes/outfit.py   ─→ OutfitService   ─┼─→ create_wardrobe_store(settings)
エージェントのツール(list_wardrobe 等) ──┘        │
                                                  ├─ WARDROBE_STORAGE=local(既定) → LocalWardrobeStore(今のまま)
                                                  └─ WARDROBE_STORAGE=gcs           → GcsWardrobeStore
                                                                                       └─ gs://<バケット>/<接頭辞>/...
```

バケットの中の置き場所(接頭辞の既定は `wardrobe`):

```
gs://ai-agent-hackathon-508804-wardrobe/
└── wardrobe/
    ├── index.json        # ローカルの index.json と同じ形式
    └── images/
        └── cloth-20261008-153000-ab12cd.jpg
```

ログインを入れるときは、接頭辞を `users/<ユーザーID>/wardrobe` のようにユーザーごとに変えれば済む(今回は固定)。

## 3. API 設計

**変更なし。** パス・リクエスト・レスポンスの形は spec 010 / 011 のまま。

エラーの扱いだけ変える。保存先を読めないとき(Cloud Storage につながらない・権限が無い)は 502 を返す。

| エンドポイント | 今 | 変更後 |
| --- | --- | --- |
| `GET /api/v1/wardrobe/items` | 例外にならない(ローカルは読めなければ 0 件) | 保存先を読めなければ 502 |
| `GET /api/v1/wardrobe/images/{image}` | 無ければ 404 | 無ければ 404、保存先を読めなければ 502 |
| `POST /api/v1/outfit/suggest`・`/outfit/image` | (ローカルは例外にならない) | 保存先を読めなければ 502 |

ローカルの `list_entries` は今までどおり例外を出さない(壊れた `index.json` は 0 件)ため、既定の設定では応答は変わらない。

## 4. データモデル

### 4.1 設定(`app/core/config.py`。`.env.example` にも追加する)

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `WARDROBE_STORAGE` | `local` | 手持ちの服の保存先。`local`(`CLOTH_INDEX_PATH` のフォルダ)/ `gcs`(Cloud Storage) |
| `WARDROBE_GCS_BUCKET` | 空 | `gcs` のときのバケット名。本番は `ai-agent-hackathon-508804-wardrobe` |
| `WARDROBE_GCS_PREFIX` | `wardrobe` | バケットの中の置き場所(接頭辞)。末尾の `/` は付けない |

`gcs` なのにバケット名が空の場合は、起動は止めず、保存先を使う操作のときに `WardrobeStoreError`(→ 502)にする。
本番で設定を間違えても、服以外の機能(MV 検索など)は動き続けるようにするため。

### 4.2 保存する中身

`index.json` と写真の形式はローカルと同じ(spec 010 の 4.)。Cloud Storage では次のメタデータを付ける。

| オブジェクト | Content-Type |
| --- | --- |
| `index.json` | `application/json; charset=utf-8` |
| 写真 | 登録時の MIME タイプ(`image/jpeg` など) |

写真を読み出すときの MIME タイプは、ローカルと同じく拡張子から決める(メタデータを取りに行く通信を増やさないため)。

## 5. フロントエンド設計

**変更なし。**

## 6. バックエンド設計

### 6.1 ファイル

| ファイル | 変更 |
| --- | --- |
| `app/services/wardrobe_store.py` | `index.json` の組み立て・読み取りと、服 1 点の削除の処理を、ローカルと Cloud Storage で共通に使える関数に切り出す(ローカルの動きは変えない)。設定から保存先を選ぶ `create_wardrobe_store(settings)` を追加する |
| `app/services/wardrobe_gcs.py`(新規) | `GcsWardrobeStore`。`google-cloud-storage` を import するのはこのファイルだけ |
| `app/services/wardrobe_registry.py` | 保存先を `create_wardrobe_store` で作る。一覧・写真の読み出しでも `WardrobeStoreError` を `WardrobeError` に変換する |
| `app/api/routes/wardrobe.py` | `GET /items` で `WardrobeError` を HTTP に変換する(他のハンドラと同じ書き方。ルータにロジックは足さない) |
| `app/services/outfit.py` | 保存先を `create_wardrobe_store` で作る。保存先の読み出しの失敗を `OutfitError`(502)に変換する |
| `app/services/wardrobe.py` | エージェントのツールが、`index.json` を直接読むのをやめて `create_wardrobe_store(settings).list_entries()` を使う |
| `scripts/run_agent.py`・`run_agent_loop.py` | `--index` を指定したときは `wardrobe_storage=local` も上書きする(指定したファイルを必ず読む) |
| `app/core/config.py`・`backend/.env.example` | 4.1 の設定を追加 |
| `backend/env.deploy.yaml` | `WARDROBE_STORAGE: 'gcs'` と `WARDROBE_GCS_BUCKET` を追加 |
| `pyproject.toml`・`uv.lock` | `uv add google-cloud-storage` |

### 6.2 `create_wardrobe_store(settings) -> WardrobeStore`

- `local` → `LocalWardrobeStore(settings.cloth_index_file)`(今と同じ)。
- `gcs` → `GcsWardrobeStore(bucket_name, prefix, project)`。`wardrobe_gcs` は関数の中で import する(ローカルのときに Cloud Storage のライブラリを読み込まないため)。

### 6.3 `GcsWardrobeStore`

コンストラクタではネットワークにつながない。最初の操作のときにクライアントを作る。
クライアント(`google.cloud.storage.Client`)はプロセス内で使い回す(`lru_cache`)。リクエストごとに作ると認証の処理が毎回走るため。
テストでは、バケットの偽物をコンストラクタの引数で渡す。

| メソッド | 処理 |
| --- | --- |
| `list_entries()` | `index.json` を読む。無ければ `[]`。読めない・壊れている場合は `WardrobeStoreError` |
| `add(...)` | ① 写真をアップロードする(名前はローカルと同じ `build_file_name`。衝突しない)→ ② `index.json` に 1 件足して書き戻す(6.4)。② が失敗したら ① の写真を消してから `WardrobeStoreError` |
| `delete_item(id)` | `index.json` から服を消して書き戻す(6.4)→ 写真に服が残らなければ写真を消す。写真を消すのに失敗してもログだけ出す(一覧からは消えているため) |
| `read_image(name)` | ファイル名をローカルと同じ規則(`IMAGE_NAME`)で確かめ、`images/<name>` を読む。無ければ `None`。読めなければ `WardrobeStoreError` |

Cloud Storage の例外(`google.api_core.exceptions.GoogleAPIError`、認証の失敗など)は、すべて `WardrobeStoreError` に包む。
「無い」(`NotFound`)だけは上の表のとおり `[]` / `None` で返す。

### 6.4 同時に書き込まれたときの扱い(AC-7)

ローカルはプロセス内のロックで順番待ちさせているが、サーバーが複数台になると効かない。
Cloud Storage では、オブジェクトの世代番号(generation)を使った**条件付きの書き込み**を使う。

```
1. index.json を読み、そのときの世代番号を覚える(無ければ 0)
2. 中身を書き換える(1 件足す / 1 点消す)
3. 「世代番号が 1. のままなら書く」という条件で書き戻す(if_generation_match)
4. 条件を満たさない(412。他の誰かが先に書いた)なら 1. からやり直す。最大 5 回
```

5 回とも失敗したら `WardrobeStoreError`。プロセス内でも、ローカルと同じくロックで直列にする(同じサーバー内の無駄なやり直しを減らすため)。

### 6.5 エージェントのツール(AC-9・AC-10)

- `list_wardrobe` / `search_wardrobe` は、呼ばれるたびに `create_wardrobe_store(bound).list_entries()` を読み、服の一覧(`WardrobeItem`)にする。登録・削除はすぐに反映される(今と同じ)。
- 服が 0 件のときの案内文は、保存先がローカルならファイルのパス、Cloud Storage なら `gs://<バケット>/<接頭辞>/index.json` を出す。
- Cloud Storage を読めないときは、例外にせず `status="error"` と理由を返す(エージェントが利用者に説明する。spec 006 と同じ考え方)。
- 既存の `load_wardrobe(index_file)` は残す(spec 005 の CLI・テストが使うため)。

## 7. Gemini プロンプト設計

**変更なし。**

## 8. エラーハンドリング / 非機能

- 保存先を読み書きできないときは、ログに例外の種類とメッセージを出す(認証情報やバケットの中身は出さない)。利用者には 502 と「服を保存できませんでした」などの今の文言を返す。
- タイムアウトは `google-cloud-storage` の既定(60 秒)を使う。
- 性能: 一覧・提案のたびに `index.json`(数 KB〜数十 KB)を 1 回読む。数十〜数百ミリ秒の増加を見込む。
- 費用: 写真 1 枚 1 MB 程度 × 数百枚でも数百 MB。保存料金は月数十円程度。

### 8.1 GCP 側の設定(Claude が gcloud で実行する。実行前にコマンドを提示して承認を得る)

```bash
# バケットを作る(東京、非公開、バケット単位の権限管理)
gcloud storage buckets create gs://ai-agent-hackathon-508804-wardrobe \
  --project ai-agent-hackathon-508804 --location asia-northeast1 \
  --uniform-bucket-level-access --public-access-prevention

# Cloud Run の実行用サービスアカウントに、このバケットのオブジェクトの読み書きだけを許可する
gcloud storage buckets add-iam-policy-binding gs://ai-agent-hackathon-508804-wardrobe \
  --member serviceAccount:872278396120-compute@developer.gserviceaccount.com \
  --role roles/storage.objectUser
```

- `roles/storage.objectUser` は、オブジェクトの読み取り・作成・削除・一覧ができる。バケット自体の削除や権限の変更はできない。
- ローカルから Cloud Storage を試すメンバーは、自分の Google アカウントにも同じロールが必要(プロジェクトの編集者なら不要)。
- Cloud Storage の API(`storage.googleapis.com`)が有効になっているかを最初に確かめる。

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend unit | `GcsWardrobeStore` の保存・一覧・削除・写真の読み出し・ファイル名の検査 | pytest。バケットの偽物(`tests/gcs_stub.py`。メモリ上の dict と世代番号)を渡す |
| backend unit | 同時書き込み(AC-7) | 偽物で、読み取りと書き戻しの間に世代番号を進め、やり直して両方の登録が残ることを確かめる |
| backend unit | 失敗時(AC-6) | 偽物が例外を投げる → `WardrobeStoreError`。`add` の失敗で写真が残らない |
| backend unit | `create_wardrobe_store` の切り替え | 既定 → `LocalWardrobeStore`、`gcs` → `GcsWardrobeStore` |
| backend unit | エージェントのツール(AC-9・AC-10) | 偽物のバケットに登録 → `list_wardrobe` / `search_wardrobe` が返す。ローカルの既存テストはそのまま通る |
| backend api | `GET /wardrobe/items` などの 502 | `dependency_overrides` で失敗する保存先を差し込む |
| 既存 | spec 010 / 011 / 006 のテスト | 変更なしで通ること(AC-1) |
| 手動 | AC-2〜AC-5・AC-8・AC-9 | 実際のバケットで、ローカル起動(`WARDROBE_STORAGE=gcs`)→ 画面から登録・一覧・提案・削除 → CLI のエージェントに聞く → 再起動して残っているか。デプロイ後に本番でも確認 |

Cloud Storage を実際に呼ぶテストは書かない(CLAUDE.md)。
