# tx_hackathon_gc

Flutter(フロント) + FastAPI(バックエンド) + Gemini on Google Cloud を組み合わせたアプリケーション。
**SPEC 駆動開発**(要件 → 設計 → タスク → 実装)で開発を進める。

> このリポジトリの「正」となるドキュメントは本 README です。構成・手順・方針を変更したら、**同じコミットで README も更新**してください(運用ルールは [CLAUDE.md](CLAUDE.md) 参照)。

---

## 1. 技術スタック

| 領域 | 採用技術 | 備考 |
| --- | --- | --- |
| フロントエンド | Flutter 3.41.x / Dart 3.11.x | Web / iOS / Android をターゲットに生成済み。開発は Web 中心 |
| バックエンド | Python 3.12 / FastAPI | `app/` 配下にレイヤ分割(api / services / schemas / core) |
| パッケージ管理 | uv | `backend/pyproject.toml` + `backend/uv.lock` で固定 |
| エージェント基盤 | Agent Development Kit (ADK) | `google-adk`。`LlmAgent` + `Runner` で Gemini を呼ぶ。ツール実行への拡張が前提 |
| 外部 API | Gemini(Google Cloud Vertex AI) | ADK 経由で呼び出す。**認証は ADC**(鍵ファイルは使わない) |
| メディア生成 | 画像 `gemini-3.1-flash-lite-image` / 動画 `gemini-omni-1.1-flash-preview` | エージェントのツールとして呼ばれる(4.4) |
| 実行環境 | Docker Compose | フロント / バックを 1 コマンドで同時起動 |
| 設定管理 | pydantic-settings / `.env` | 秘匿情報は Git 管理外 |

## 2. アーキテクチャ

### 2.1 全体構成

```
┌─────────────────────────────────────────────────────────────────────┐
│ ブラウザ / モバイル                                                 │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ Flutter App  (localhost:8080)                                 │  │
│  │                                                               │  │
│  │   features/<機能>/  ── 画面(Widget) + 状態                    │  │
│  │            │                                                  │  │
│  │            ▼                                                  │  │
│  │   features/<機能>/*_repository.dart  ── データアクセス        │  │
│  │            │                                                  │  │
│  │            ▼                                                  │  │
│  │   core/api_client.dart  ── HTTP / JSON / 例外変換             │  │
│  └───────────────────────────────┬───────────────────────────────┘  │
└──────────────────────────────────┼──────────────────────────────────┘
                                   │ HTTP (JSON)  /api/v1/**
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ FastAPI Backend  (localhost:8000)                                   │
│                                                                     │
│   app/main.py         ── アプリ生成 / CORS / lifespan               │
│            │                                                        │
│   app/api/router.py   ── ルータ集約                                 │
│            │                                                        │
│   app/api/routes/     ── エンドポイント(入出力の検証と HTTP 変換)   │
│            │                                                        │
│   app/services/       ── ビジネスロジック / エージェント実行        │
│            │              例外は業務例外(AgentError 等)に変換       │
│   app/schemas/        ── Pydantic モデル(API 契約)                  │
│   app/core/           ── 設定(config) / ロギング                    │
└──────────────────────────────────┼──────────────────────────────────┘
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Agent Development Kit (ADK)                                         │
│                                                                     │
│   Runner ── 実行制御。Event ストリームを返す                        │
│     ├─ InMemorySessionService ── 会話セッション(プロセス内)         │
│     └─ LlmAgent ── model / instruction / tools を持つエージェント   │
│           └─ tools: generate_image / generate_video /               │
│                    list_wardrobe / search_wardrobe                  │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │ google-genai SDK (ADC 認証)
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Google Cloud                                                        │
│   Vertex AI ── Gemini (モデルは GEMINI_MODEL で指定)                │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 レイヤの責務(この境界を守る)

| レイヤ | 責務 | やってはいけないこと |
| --- | --- | --- |
| `app/api/routes/` | リクエスト検証、HTTP ステータスへの変換、DI | ビジネスロジック、SDK の直接呼び出し |
| `app/services/` | ユースケース実装、外部 API 呼び出し、例外の正規化 | `HTTPException` を投げる、FastAPI に依存する |
| `app/schemas/` | API の入出力契約(Pydantic) | 永続化や外部 API のモデルを兼ねる |
| `app/core/` | 設定・ロギングなど横断関心事 | 機能固有のロジック |
| `lib/features/*/` | 画面と状態、機能ごとの Repository | 他 feature の内部への直接依存 |
| `lib/core/` | HTTP クライアント、共通設定 | 画面固有の処理 |

### 2.3 リクエストの流れ(チャット機能の例)

```
ユーザー入力
  → ChatScreen._send()
  → ChatRepository.sendMessage()
  → POST /api/v1/chat                     (ApiClient)
  → chat.py: ChatRequest で検証            (routes)
  → AgentService.generate_reply()          (services)
      ├─ create_session()                  # リクエストごとに使い捨て
      ├─ append_event() × history 件数     # 過去のやり取りを文脈として投入
      └─ Runner.run_async()                # LlmAgent が Gemini を呼ぶ
           → Event ストリームから is_final_response() のテキストを取得
  → ChatResponse(reply, model)
  → 画面に吹き出しとして描画
```

失敗時は `AgentError` → HTTP 502 → `ApiException` → 画面上のバナー、という順に変換される。

会話履歴はサーバに保持せず、毎回クライアントから受け取って再現する(ステートレス)。
複数インスタンスに分散してもセッションの偏りが起きない。

### 2.4 ディレクトリ構成

```
tx_hackathon_gc/
├── README.md                 # 本ドキュメント(構成・手順の正)
├── CLAUDE.md                 # Claude Code 向けの作業ルール
├── docker-compose.yml        # フロント + バックの同時起動
├── .env.example              # compose 用(ADC のパス)。.env は Git 管理外
├── .github/
│   └── workflows/ci.yml      # push / PR 時の Lint・型チェック・テスト
├── backend/                  # FastAPI + uv
│   ├── pyproject.toml / uv.lock
│   ├── .env.example          # 環境変数の雛形(.env は Git 管理外)
│   ├── Dockerfile
│   ├── app/
│   │   ├── main.py           # エントリポイント(create_app)
│   │   ├── api/
│   │   │   ├── router.py     # ルータ集約
│   │   │   └── routes/       # health.py, chat.py, ...
│   │   ├── core/             # config.py, logging.py
│   │   ├── schemas/          # Pydantic モデル
│   │   ├── services/         # agent.py, agent_loop.py, verification.py, media.py,
│   │   │                     #   cloth_index.py, wardrobe.py ほか
│   │   ├── created_images/   # 生成された画像の保存先(Git 管理外)
│   │   └── created_videos/   # 生成された動画の保存先(Git 管理外)
│   ├── scripts/
│   │   ├── run_agent.py      # 対話でエージェントを動かす CLI
│   │   ├── run_agent_loop.py # 生成 → 検証 → 再生成 を繰り返す CLI
│   │   └── build_cloth_index.py # 服画像から属性インデックスを作る CLI
│   └── tests/                # pytest
│       ├── sample_images/        # 服のサンプル画像
│       └── sample_cloth_indexs/  # 抽出した属性インデックス(index.json)
├── frontend/                 # Flutter
│   ├── pubspec.yaml
│   ├── Dockerfile            # dev(ホットリロード) / prod(nginx) の 2 ステージ
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/             # app_config.dart, api_client.dart
│   │   └── features/         # 機能ごと(chat/ など)
│   └── test/
├── docs/
│   └── spec/                 # SPEC 駆動開発のドキュメント
│       ├── README.md         # 運用ルール
│       ├── _template/        # requirements / design / tasks の雛形
│       ├── 000-local-dev-environment/
│       ├── 001-gemini-adk-chat/
│       ├── 002-agent-cli-multimodal/
│       ├── 003-media-generation-tools/
│       ├── 004-agent-loop/
│       ├── 005-cloth-index/
│       └── 006-wardrobe-tools/
└── infra/
    └── secrets/              # SA キーを使う例外ケース用(Git 管理外。通常は空)
```

---

## 3. セットアップ

### 3.1 前提ツール

| ツール | 確認コマンド | 補足 |
| --- | --- | --- |
| Flutter 3.41+ | `flutter --version` | Web 開発なら Chrome も必要 |
| uv | `uv --version` | Python 3.12 は uv が自動取得する |
| Docker Desktop | `docker compose version` | Compose v2 |
| gcloud CLI | `gcloud --version` | **必須**。ADC の作成に使う(3.3) |

### 3.2 環境変数

`.env` は 2 つある。役割が違うので混同しないこと(どちらも Git 管理外)。

| ファイル | 役割 |
| --- | --- |
| `backend/.env` | アプリの設定(プロジェクト ID・モデル名など) |
| `.env`(リポジトリ直下) | docker compose 用。ADC のパス(`GCLOUD_CONFIG_DIR`)を指定する |

```bash
cp backend/.env.example backend/.env
cp .env.example .env            # Docker Compose を使う場合のみ
```

`backend/.env` の主な項目:

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `ENVIRONMENT` | `local` | `local` / `dev` / `prod`。`local` 以外は JSON ログになる |
| `GOOGLE_GENAI_USE_VERTEXAI` | `true` | `true`=Vertex AI 経由 / `false`=AI Studio の API キー |
| `GOOGLE_CLOUD_PROJECT` | (必須) | GCP プロジェクト ID |
| `GOOGLE_CLOUD_LOCATION` | `global` | Vertex AI のロケーション。新しいモデルは `global` のみ提供 |
| `GOOGLE_API_KEY` | 空 | `GOOGLE_GENAI_USE_VERTEXAI=false` のときのみ使用 |
| `ADK_APP_NAME` | `tx-hackathon-gc` | ADK のアプリ名(セッションの名前空間) |
| `AGENT_NAME` | `chat_agent` | エージェント名。ADK の Event の author になる |
| `AGENT_DESCRIPTION` | (説明文) | エージェントの役割。マルチエージェント化時の選択材料になる |
| `GEMINI_SYSTEM_INSTRUCTION` | (指示文) | エージェントの役割・口調。`LlmAgent` の instruction になる |
| `GEMINI_MODEL` | `gemini-2.5-flash` | 使用モデル。利用可能な名前は 9. の方法で確認できる |
| `GEMINI_TEMPERATURE` / `GEMINI_MAX_OUTPUT_TOKENS` | `0.7` / `2048` | 生成パラメータ |
| `IMAGE_MODEL` | `gemini-3.1-flash-lite-image` | 画像生成モデル |
| `VIDEO_MODEL` | `gemini-omni-1.1-flash-preview` | 動画生成モデル(Interactions API 経由) |
| `CREATED_IMAGES_DIR` / `CREATED_VIDEOS_DIR` | `app/created_images` / `app/created_videos` | 生成物の保存先(backend/ からの相対) |
| `MEDIA_GENERATION_TIMEOUT` | `300` | 動画生成の待ち時間上限(秒) |
| `VERIFIER_MODEL` | `gemini-2.5-flash` | ループの検証に使うモデル(生成モデルとクォータを分ける) |
| `LOOP_MAX_ITERATIONS` | `3` | 生成 → 検証 を繰り返す上限回数 |
| `CLOTH_INDEX_MODEL` | `gemini-2.5-flash` | 服画像から属性を抽出するモデル |
| `CLOTH_INDEX_PATH` | `tests/sample_cloth_indexs/index.json` | エージェントが参照する服インデックス |

### 3.3 Google Cloud 認証(ADC)

**Gemini の呼び出し認証は ADC(Application Default Credentials)を基本とする。**
API キーやサービスアカウントキーをリポジトリや `.env` に置かない運用にするため。

#### 手順(初回のみ)

```bash
gcloud auth login                                    # gcloud 自体のログイン
gcloud config set project <PROJECT_ID>
gcloud auth application-default login                # ★ ADC を作成
gcloud auth application-default set-quota-project <PROJECT_ID>   # 課金/クォータ先を指定
gcloud services enable aiplatform.googleapis.com     # Vertex AI API の有効化
```

作成された資格情報は gcloud の設定ディレクトリに置かれる(**コミット対象外・共有厳禁**)。

```bash
gcloud info --format="value(config.paths.global_config_dir)"
# Windows: C:\Users\<ユーザー名>\AppData\Roaming\gcloud
# macOS/Linux: ~/.config/gcloud
```

アプリ側は `backend/.env` の `GOOGLE_CLOUD_PROJECT` / `GOOGLE_CLOUD_LOCATION` だけを見る。
**資格情報そのものは `.env` に書かない。**

#### ネイティブ起動の場合

上記の ADC がそのまま使われる。追加設定は不要。

#### Docker Compose の場合

ホストの gcloud 設定ディレクトリをコンテナの `/root/.config/gcloud` に read-only でマウントする。
マウント元のパスはリポジトリ直下の `.env` で指定する。

```bash
cp .env.example .env
# .env を開き、GCLOUD_CONFIG_DIR に上記コマンドで確認したパスを設定する
```

> `.env` が 2 つある点に注意。
> **リポジトリ直下の `.env`** = compose 用(ホスト側のパス)、**`backend/.env`** = アプリの設定。どちらも Git 管理外。

#### 例外: サービスアカウントキーを使う場合

CI や、ADC を用意できない環境でのみ使用する。`infra/secrets/gcp-sa.json`(Git 管理外)に置き、
`docker-compose.yml` の `GOOGLE_APPLICATION_CREDENTIALS` と `./infra/secrets` のマウント行のコメントを外す。
Cloud Run などにデプロイする場合は、キーではなく**サービスアカウントをリソースに紐づける**方式を使う。

---

## 4. 起動方法

### 4.1 Docker Compose(フロント + バックを同時起動)

```bash
cp .env.example .env            # 初回のみ。GCLOUD_CONFIG_DIR を自分の環境に合わせる(3.3)
cp backend/.env.example backend/.env   # 初回のみ。GOOGLE_CLOUD_PROJECT を設定する
docker compose up --build
```

| URL | 内容 |
| --- | --- |
| http://localhost:8080 | Flutter Web アプリ |
| http://localhost:8000/docs | FastAPI の Swagger UI |
| http://localhost:8000/api/v1/health | ヘルスチェック |

停止は `docker compose down`(ボリュームも消す場合は `-v`)。

### 4.2 ネイティブ起動(開発中はこちらが高速)

バックエンド:

```bash
cd backend
uv sync
uv run uvicorn app.main:app --reload --port 8000
```

フロントエンド:

```bash
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

### 4.3 エージェントを CLI で動かす(サーバ・フロント不要)

プロンプトやツールの試行錯誤は、この CLI が一番速い。API と同じ `AgentService` を通るため、
ここで確認した挙動はそのまま `POST /api/v1/chat` でも再現する。

```bash
cd backend

# 対話モード(履歴を保持して会話が続く)
uv run python scripts/run_agent.py

# 単発実行
uv run python scripts/run_agent.py -m "こんにちは"

# 画像を添付
uv run python scripts/run_agent.py -m "この画像を説明して" -f photo.png

# Cloud Storage の動画(ダウンロードせず URI のまま渡る)
uv run python scripts/run_agent.py -m "この動画を要約して" -f gs://bucket/movie.mp4

# モデルを一時的に変えて試す
uv run python scripts/run_agent.py -m "要約して" --model gemini-2.5-flash
```

対話モード中のコマンド:

| コマンド | 動作 |
| --- | --- |
| `/file <パス\|gs://...>` | 次のメッセージに画像・動画を添付する |
| `/files` | 添付予定の一覧 |
| `/clear` | 添付予定を取り消す |
| `/reset` | 会話履歴を消す |
| `/help` / `/exit` | ヘルプ / 終了(Ctrl+C でも可) |

対応形式は画像(png / jpg / gif / webp / heic)と動画(mp4 / mov / webm / avi / mpeg / flv / wmv)。
音声(mp3 / wav)と pdf も同じ経路で渡せる。

> **大きいファイルはインラインで送らない。** ローカルファイルは base64 でリクエストに載るため、
> リクエストサイズの上限に当たる。動画など大きいものは Cloud Storage に置いて `gs://` で渡す。

HTTP API から添付する場合は `attachments` を使う(省略可。既存の呼び出しは変更不要)。

```json
{
  "message": "この画像を説明して",
  "history": [],
  "attachments": [
    {"mime_type": "image/png", "data": "<base64>"},
    {"mime_type": "video/mp4", "uri": "gs://bucket/movie.mp4"}
  ]
}
```

`data`(base64)と `uri` は**どちらか一方だけ**を指定する(両方または両方なしは 422)。

### 4.4 画像 / 動画を生成する

エージェントは**画像生成・動画生成のツールを持っている**。依頼すればモデルが自分で判断して呼ぶ。
ツール名やコマンドを覚える必要はない。

```bash
cd backend
uv run python scripts/run_agent.py -m "富士山と桜の画像を作ってください"
uv run python scripts/run_agent.py -m "夕暮れの海の波の短い動画を作って"
```

| 種類 | モデル | 保存先 | 所要時間の目安 |
| --- | --- | --- | --- |
| 画像 | `IMAGE_MODEL`(既定: `gemini-3.1-flash-lite-image`) | `backend/app/created_images/` | 数秒 |
| 動画 | `VIDEO_MODEL`(既定: `gemini-omni-1.1-flash-preview`) | `backend/app/created_videos/` | 数十秒 |

ファイル名は `image-20260917-145042-ef7543.jpg` のように日時 + ランダム文字列で衝突しない。
応答には保存されたファイル名とパスが含まれる。

- 生成物は**Git 管理外**(`.gitignore` 済み)。溜まったら手動で削除してよい。
- 生成が不要な質問ではツールは呼ばれない。
- 生成に失敗してもエージェントは止まらず、失敗した理由を応答で説明する。

> **動画生成は `generateContent` では呼べない。** `gemini-omni-*` は Interactions API 専用のため、
> 実装は `client.interactions.create()` を使っている([app/services/media.py](backend/app/services/media.py))。

### 4.5 エージェントループ(生成 → 検証 → 再生成)

要望を満たすまで、エージェントが**自動で試行を繰り返す**。対話は挟まない。

```bash
cd backend

# 要望を満たすまで最大 3 周(既定)
uv run python scripts/run_agent_loop.py -m "夕焼けの海辺にいる柴犬の画像を作って"

# 上限を変える
uv run python scripts/run_agent_loop.py -n 5 -m "雪山の風景画像"

# 参考画像を渡して始める
uv run python scripts/run_agent_loop.py -m "この写真に似た雰囲気で作って" -f sample.png
```

動作:

```
要望 → 生成 → 生成物を検出 → 検証(要望と生成物を突き合わせ)
         ↑                          │
         └── 指摘と改善点を添えて ───┘  満たすまで / 上限まで
```

- **検証は生成物の中身を見る。** 画像・動画はモデルに現物を渡して判定する(ファイルの有無では判断しない)。
- 未達の場合、判定理由と改善点が次の生成指示に入る。前周までの会話も履歴として渡る。
- 各周回の「生成 / 生成物 / 判定 / 改善点」が画面に出る。
- **終了コード**: 要望を満たしたら `0`、上限まで未達なら `1`(スクリプトから使える)。
- 1 周につきモデル呼び出しは 2 回(生成 + 検証)。上限を上げるとクォータを消費する。
- 検証モデルは `VERIFIER_MODEL` で別に指定できる(既定 `gemini-2.5-flash`)。生成モデルのクォータ枯渇と切り離すため。

実行例(1 周目で画像生成がクォータ超過 → 検証が未達と判定 → 2 周目で成功):

```
[1 周目]
  生成: 画像生成のリソース制限に達したため、生成できませんでした。
  生成物: (なし)
  検証: 未達 - 画像を生成していないためです。
  改善点: 利用者の要望通りの画像を生成すること。
[2 周目]
  生成物: image-20260917-152703-4af56b.jpg
  検証: 満たした - 要望通りの画像です。
結果: 要望を満たしました(2 周)
```

> 停止の判断は**アプリ側で制御**している(ADK の `LoopAgent` は使っていない)。
> モデルに停止判断を任せると、検証を飛ばしたり止まらなかったりするため。
> 詳細は [docs/spec/004-agent-loop/design.md](docs/spec/004-agent-loop/design.md)。

### 4.6 服画像のインデックスを作る

服の写真から**素材・形・色・系統**などを抽出して JSON にする。

```bash
cd backend

# 既定(tests/sample_images → tests/sample_cloth_indexs)
uv run python scripts/build_cloth_index.py

# ディレクトリを指定
uv run python scripts/build_cloth_index.py -i path/to/images -o path/to/index

# 処理済みも作り直す
uv run python scripts/build_cloth_index.py --force
```

出力は **`index.json` の 1 ファイル**にまとまる。

```json
{
  "generated_at": "2026-09-17T15:43:10+09:00",
  "model": "gemini-2.5-flash",
  "source_dir": "tests/sample_images",
  "count": 5,
  "entries": [
    {
      "image": "image.jpeg",
      "items": [
        {
          "category": "Tシャツ",
          "material": "綿",
          "shape": "半袖クルーネック",
          "colors": ["ピンク", "黄色", "赤"],
          "pattern": "プリント",
          "style": "カジュアル",
          "notes": "「Let's Eat」と書かれた円形プリント"
        }
      ],
      "summary": "床に広げられたピンクの半袖Tシャツ。",
      "model": "gemini-2.5-flash",
      "analyzed_at": "2026-09-17T15:42:54+09:00"
    }
  ]
}
```

- 1 枚に複数の服が写っていれば `items` が複数件になる。
- **処理済みの画像は再実行時にスキップする**(`index.json` にある画像名で判定)。作り直すときは `--force`。
- 解析 1 枚ごとに `index.json` を書き出すので、途中で中断しても解析済みは残る。
- 画像以外のファイルは無視する。1 枚の解析に失敗しても残りは処理を続ける。
- 抽出項目を増やすときは [app/services/cloth_index.py](backend/app/services/cloth_index.py) の `ClothItem` に追加する。

### 4.7 手持ちの服をエージェントに参照させる

4.6 で作った `index.json` を、エージェントが**必要なときだけ**参照する。
専用のコマンドは無く、普通に聞けばよい(`run_agent.py` / `run_agent_loop.py` の両方で使える)。

```bash
cd backend
uv run python scripts/run_agent.py -m "私が持っている服を一覧で教えて"
uv run python scripts/run_agent.py -m "手持ちのデニムに合うトップスはどれ？"
uv run python scripts/run_agent_loop.py -m "手持ちの服を使った春コーデの画像を作って"

# 別のインデックスを参照する
uv run python scripts/run_agent.py --index path/to/index.json -m "手持ちの服は？"
```

| ツール | 使われる場面 |
| --- | --- |
| `list_wardrobe` | 「手持ちの服を教えて」など全体を見るとき |
| `search_wardrobe(keyword)` | 「デニムに合う服は?」など色・素材・種類で絞るとき |

- **呼ぶ判断はモデルに任せている。** 服と無関係な質問(例: 「1+1は?」)ではインデックスを読まない。
- インデックスが無い場合もエラーにならず、「作成されていない」と応答する。
- 参照先は `CLOTH_INDEX_PATH`(既定 `tests/sample_cloth_indexs/index.json`)または `--index` で指定する。
- 渡すのは属性テキストのみで、画像そのものは渡さない。

---

## 5. テスト / 静的解析

### 5.1 ローカル

```bash
# バックエンド
cd backend
uv run python -m pytest          # テスト
uv run ruff check .              # Lint
uv run ruff format .             # フォーマット
uv run python -m mypy app scripts  # 型チェック(下記の注意参照)

# フロントエンド
cd frontend
dart format .                    # フォーマット
flutter analyze                  # 静的解析
flutter test                     # テスト
```

> **Windows のアプリケーション制御ポリシーについて**
> - `uv run pytest`(`pytest.exe`)はブロックされることがあるため、`uv run python -m pytest` を使う。
> - mypy はネイティブ拡張(`*_mypyc.pyd`)がブロックされ、現状この開発マシンでは実行できない。
>   型チェックは Docker(`docker compose run --rm backend python -m mypy app`)または CI(5.2)で実行する。

### 5.2 CI(GitHub Actions)

`main` への push と `main` 向けの PR で [.github/workflows/ci.yml](.github/workflows/ci.yml) が自動実行される
(手動実行は Actions タブの "Run workflow")。3 ジョブが並列に走る。

| ジョブ | 実行内容 |
| --- | --- |
| `backend` | `uv sync --frozen` → `ruff check` → `ruff format --check` → **`mypy app scripts`** → `pytest` |
| `frontend` | `flutter pub get` → `dart format --set-exit-if-changed` → `flutter analyze` → `flutter test` |
| `docker` | `docker compose config` の検証 → バックエンドイメージのビルド |

- ローカルで mypy が動かない環境でも、**型チェックは push 後に CI が必ず実行する**。
- 依存は `uv.lock` / `pubspec.lock` に固定され、CI はキャッシュを使って再現性のある環境で検証する。
- 外部 API(Gemini)は呼ばない。テストは全てスタブで完結させること。
- **ステータスチェック名 = ジョブの `name:`**。ルールセット(5.3)で指定するため、
  `backend` / `frontend` / `docker` の 3 つは安易に変更しない。変更する場合はルールセット側も直す。

### 5.3 CI を必須にする(ブランチ保護)

CI は作っただけでは「落ちてもマージできる」状態。`main` を保護して初めてゲートになる。

**前提**: 一度 push して CI を実行しておく。ステータスチェックは
**過去に実行された履歴からしか選択できない**ため、未実行だと候補に出てこない。

**手順**: リポジトリの **Settings → Rules → Rulesets → New ruleset → New branch ruleset**

| 設定項目 | 値 |
| --- | --- |
| Ruleset Name | `protect-main` |
| Enforcement status | `Active`(まず様子を見るなら `Evaluate` でドライラン) |
| Target branches | Add target → **Include default branch**(= `main`) |
| Restrict deletions | ON |
| Block force pushes | ON |
| Require a pull request before merging | ON(Required approvals は 1 人開発なら `0`) |
| Require status checks to pass | ON → Add checks で `backend` / `frontend` / `docker` を追加(Source: GitHub Actions) |
| Require branches to be up to date before merging | 任意(ON にすると main 更新のたびに再実行が必要) |

注意点:

- **private リポジトリでのブランチ保護 / ルールセットは有料プラン(Pro / Team 以上)が必要**。
  Free の private では設定できないため、public にするかプランを確認する。
- 必須にしたチェックが「一度も実行されない」状況(例: ワークフローに `paths` フィルタを足す)を作ると、
  PR が永久に pending になりマージできなくなる。必須チェックと実行条件は必ず揃える。
- 管理者も含めて例外なく適用される。緊急時は Bypass list に自分を追加するか、ルールセットを一時 `Disabled` にする。

---

## 6. SPEC 駆動開発の進め方

機能ごとに `docs/spec/<連番>-<機能名>/` を作り、**要件 → 設計 → タスク → 実装** の順で進める。
詳細は [docs/spec/README.md](docs/spec/README.md)、雛形は [docs/spec/_template/](docs/spec/_template/)。

```
docs/spec/001-user-authentication/
├── requirements.md   # なぜ / 誰が何をできるか / 受け入れ基準(AC)
├── design.md         # どう作るか(API・データモデル・画面・エラー・テスト方針)
└── tasks.md          # 30〜90 分粒度の作業分解(チェックボックス)
```

原則:

1. **requirements.md が承認されるまで design.md を書かない。design.md が承認されるまで実装しない。**
2. 受け入れ基準(AC)はテスト可能な粒度で書き、`tasks.md` の各タスクから参照する。
3. 実装中に設計が変わったら、コードと同じコミットで `design.md` を更新する。
4. 機能完了時に本 README の機能一覧 / アーキテクチャを更新する。
5. ブランチ名は spec 名に揃える(例: `feat/001-user-authentication`)。

### 実装済み / 進行中の機能

| spec | 機能 | ステータス |
| --- | --- | --- |
| [000-local-dev-environment](docs/spec/000-local-dev-environment/) | ローカル開発環境の整備(疎通用チャット含む) | 実装完了 / `docker compose up` の実起動確認待ち |
| [001-gemini-adk-chat](docs/spec/001-gemini-adk-chat/) | Agent ADK による Gemini 呼び出し(認証は ADC) | done |
| [002-agent-cli-multimodal](docs/spec/002-agent-cli-multimodal/) | エージェント単体実行 CLI とマルチモーダル入力(画像・動画) | done |
| [003-media-generation-tools](docs/spec/003-media-generation-tools/) | 画像 / 動画生成ツール(ADK Function Calling) | done |
| [004-agent-loop](docs/spec/004-agent-loop/) | エージェントループ(生成 → 検証 → 再生成) | done |
| [005-cloth-index](docs/spec/005-cloth-index/) | 服画像から属性インデックスを作成 | done |
| [006-wardrobe-tools](docs/spec/006-wardrobe-tools/) | 服インデックスをエージェントから参照(ツール) | done |

---

## 7. 新しい機能を追加するときの手順

1. `docs/spec/_template/` をコピーして `docs/spec/<連番>-<機能名>/` を作る。
2. `requirements.md` → `design.md` → `tasks.md` を順に作成し、レビューを受ける。
3. バックエンド: `app/schemas/` にモデル → `app/services/` にロジック → `app/api/routes/` にエンドポイント → `app/api/router.py` に登録。
4. フロントエンド: `lib/features/<機能>/` にモデル / Repository / 画面を追加。
5. テストを追加し(`backend/tests/`, `frontend/test/`)、`pytest` と `flutter test` を通す。
6. `tasks.md` のチェックを埋め、README の機能一覧を更新する。

作業中の Git 操作は §8 のコマンド一覧を参照。

---

## 8. Git コマンド一覧(初心者向け)

### 8.1 まず知っておく 4 つの場所

```
①作業ツリー          ②ステージ            ③ローカルリポジトリ    ④リモート(GitHub)
 手元のファイル  ──→  コミット予定の箱  ──→  手元の履歴       ──→  みんなの履歴
                git add            git commit          git push

                         ←────────────────────────────────  git pull
```

「保存した = Git に記録された」ではない。`add`(②へ) → `commit`(③へ) → `push`(④へ)の 3 段階を通す。

### 8.2 初回だけやること

```bash
# 名前とメールアドレス(コミットに記録される)
git config --global user.name "あなたの名前"
git config --global user.email "you@example.com"

# 既定ブランチ名を main にする / pull は rebase にして履歴を綺麗に保つ
git config --global init.defaultBranch main
git config --global pull.rebase true

# GitHub リポジトリを作って紐づける(gh CLI がある場合)
gh auth login
gh repo create tx_hackathon_gc --private --source=. --remote=origin

# gh を使わない場合(GitHub の Web 画面で空リポジトリを作ってから)
git remote add origin https://github.com/<ユーザー名>/tx_hackathon_gc.git

# 最初のコミットと push
git add .
git commit -m "chore: 開発環境の初期構築"
git push -u origin main
```

### 8.3 機能開発の 1 サイクル(この流れを繰り返す)

```bash
# 1. 最新の main から作業ブランチを作る(ブランチ名は spec に合わせる)
git switch main
git pull
git switch -c feat/001-user-authentication

# 2. コードを編集する …

# 3. 何を変えたか確認する
git status          # 変更されたファイルの一覧
git diff            # 変更内容そのもの

# 4. コミットする
git add .                                   # 全部を対象にする
git add backend/app/api/routes/auth.py      # ファイルを選ぶ場合
git commit -m "feat: ログイン API を追加"

# 5. GitHub に送る(初回は -u、2 回目以降は git push だけでよい)
git push -u origin feat/001-user-authentication

# 6. PR を作る → CI(backend / frontend / docker)が緑になったらマージ
gh pr create --fill
gh pr checks            # CI の状況を確認
gh pr merge --squash    # Web 画面のマージボタンでもよい

# 7. 後片付け
git switch main
git pull
git branch -d feat/001-user-authentication
```

### 8.4 よく使うコマンド

**確認する**

| コマンド | 何ができるか |
| --- | --- |
| `git status` | 今どのブランチにいて、何が変更 / ステージされているか |
| `git diff` | まだ `add` していない変更内容 |
| `git diff --staged` | `add` 済み(コミット予定)の変更内容 |
| `git log --oneline -10` | 直近 10 件のコミット履歴 |
| `git log --oneline --graph --all` | ブランチの分岐を図で表示 |
| `git show <コミットID>` | そのコミットの変更内容 |

**記録する / 送る**

| コマンド | 何ができるか |
| --- | --- |
| `git add <ファイル>` / `git add .` | コミット対象に加える |
| `git commit -m "メッセージ"` | 記録する |
| `git commit -am "メッセージ"` | 変更済みファイルを add + commit(新規ファイルは対象外) |
| `git push` | GitHub に送る |
| `git push -u origin <ブランチ名>` | 新しいブランチを初めて送るとき |
| `git pull` | GitHub の変更を取り込む |
| `git fetch` | 取り込まずに最新情報だけ取得する |

**ブランチ**

| コマンド | 何ができるか |
| --- | --- |
| `git branch` | ローカルのブランチ一覧 |
| `git switch <ブランチ名>` | ブランチを切り替える |
| `git switch -c <ブランチ名>` | 作って切り替える |
| `git switch -` | 直前にいたブランチに戻る |
| `git branch -d <ブランチ名>` | マージ済みブランチを削除 |
| `git merge main` | 作業ブランチに main の変更を取り込む |

**取り消す**(よく使う順)

| やりたいこと | コマンド | 補足 |
| --- | --- | --- |
| ファイルの変更を捨てて元に戻す | `git restore <ファイル>` | **戻せないので注意** |
| `add` を取り消す(変更は残す) | `git restore --staged <ファイル>` | |
| 直前のコミットメッセージを直す | `git commit --amend -m "新しいメッセージ"` | **push 前だけ** |
| 直前のコミットを取り消す(変更は残す) | `git reset --soft HEAD~1` | **push 前だけ** |
| push 済みのコミットを打ち消す | `git revert <コミットID>` | 打ち消すコミットを新たに積む。履歴を壊さない |
| 作業を一時退避する | `git stash` → 戻すときは `git stash pop` | ブランチを急いで切り替えたいとき |

**コンフリクト(競合)が起きたら**

```bash
git pull                     # ここで CONFLICT と表示される
# → エディタで <<<<<<< ======= >>>>>>> の箇所を手で直す(残す内容を決める)
git add <直したファイル>
git commit                   # マージコミットを作る(rebase 中なら git rebase --continue)

# 手に負えなくなったら中断して元に戻す
git merge --abort            # または git rebase --abort
```

### 8.5 コミットメッセージの書き方

`<種別>: <日本語で何をしたか>` の形にする。

| 種別 | 使う場面 |
| --- | --- |
| `feat` | 機能追加 |
| `fix` | バグ修正 |
| `docs` | ドキュメントのみの変更 |
| `refactor` | 挙動を変えないコード整理 |
| `test` | テストの追加 / 修正 |
| `chore` | 設定・依存関係・CI など |

```bash
git commit -m "feat: チャット履歴の保存を追加"
git commit -m "fix: 空メッセージ送信時に 500 になる問題を修正"
```

### 8.6 やってはいけないこと

| やってはいけないこと | 理由 / 代わりにすること |
| --- | --- |
| `main` に直接コミット / push | 必ずブランチを切って PR を出す(ブランチ保護で拒否される) |
| `git push --force` | 他人の履歴を壊す。保護設定でも拒否される。打ち消しは `git revert` |
| `.env` や `infra/secrets/*.json` をコミット | 資格情報の漏洩。`.gitignore` 済みだが `git add -f` で強制追加しない |
| `git reset --hard` を安易に使う | コミットしていない変更が**完全に消える**。まず `git stash` |
| 巨大な 1 コミット | レビュー不能。機能の区切りごとにコミットする |

> **もし `.env` をコミットしてしまったら**: push 前なら `git rm --cached backend/.env` してコミットし直す。
> push 済みなら履歴から消えないため、**該当する認証情報を GCP 側で無効化して作り直す**。

---

## 9. トラブルシューティング

| 症状 | 対処 |
| --- | --- |
| `GOOGLE_CLOUD_PROJECT が未設定です` | `backend/.env` にプロジェクト ID を設定する |
| 403 / PermissionDenied | `aiplatform.googleapis.com` の有効化と、ADC のアカウントに Vertex AI User ロールがあるかを確認 |
| `DefaultCredentialsError` / 401 | ADC が無い。`gcloud auth application-default login` を実行する(3.3) |
| コンテナだけ認証に失敗する | ルートの `.env` の `GCLOUD_CONFIG_DIR` が正しいか確認。`gcloud info --format="value(config.paths.global_config_dir)"` の値と一致させる |
| `Your default credentials ... quota project` の警告 | `gcloud auth application-default set-quota-project <PROJECT_ID>` を実行する |
| フロントから API が呼べない(CORS) | `backend/app/core/config.py` の `cors_origins` に接続元 URL を追加 |
| コンテナでコード変更が反映されない | Windows では `WATCHFILES_FORCE_POLLING=true`(compose 設定済み)を確認 |
| `uv run pytest` がブロックされる | `uv run python -m pytest` を使う |
| `mypy` が `DLL load failed` で落ちる | ローカルのアプリ制御ポリシーによるもの。Docker または CI で型チェックする |
| `opentelemetry.context: Failed to detach context` が ERROR ログに出る | ADK と OpenTelemetry の既知の相性問題。応答自体は正常に返るため無視してよい |
| `エージェントから空の応答が返りました` | モデル名(`GEMINI_MODEL`)が無効、または安全フィルタで応答が空。モデル名と入力内容を確認する |
| `404 Publisher model ... was not found` | そのモデルが `GOOGLE_CLOUD_LOCATION` のロケーションに無い。新しいモデルは `global` を指定する |
| `429 RESOURCE_EXHAUSTED` | モデルのクォータ超過。時間をおくか、`GEMINI_MODEL` を枯渇していないモデルに変える |
| 添付が `対応していない拡張子です` | `app/services/attachments.py` の対応表に無い形式。必要なら対応表に追加する |
| 大きい動画でリクエストが失敗する | base64 で送るとサイズ上限に当たる。Cloud Storage に置いて `gs://` で渡す(4.3) |
| `is only supported in the Interactions API` | `gemini-omni-*` を `generateContent` で呼んでいる。`client.interactions.create()` を使う |
| 画像生成の応答にファイル名が出ない | `GEMINI_SYSTEM_INSTRUCTION` を上書きしても、ツール利用の指示は `agent.py` の `TOOL_GUIDELINE` が付与する。モデルを変えた場合は追従を確認する |
| Flutter コンテナのビルドが遅い | 開発中はネイティブ起動(4.2)を使い、compose は結合確認時に使う |

---

## 10. 利用可能な Gemini モデルを調べる

`GEMINI_MODEL` に何を指定できるかは、プロジェクトから見えるモデル一覧で確認する。

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT=$(gcloud config get-value project)

# global ロケーションで使えるモデル
curl -s -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: $PROJECT"   "https://aiplatform.googleapis.com/v1beta1/publishers/google/models?pageSize=200"   | grep -o '"name": *"publishers/google/models/gemini-[^"]*"'
```

一覧に出ていても実際の呼び出しが 404 になる場合がある(ロケーション未提供)。
その場合は `GOOGLE_CLOUD_LOCATION=global` を試す。実際に使えるかは次で確認できる。

```bash
curl -s -o /dev/null -w "%{http_code}
"   -H "Authorization: Bearer $TOKEN" -H "X-Goog-User-Project: $PROJECT"   -H "Content-Type: application/json"   -d '{"contents":[{"role":"user","parts":[{"text":"say OK"}]}]}'   "https://aiplatform.googleapis.com/v1/projects/$PROJECT/locations/global/publishers/google/models/<モデル名>:generateContent"
# 200 なら使える / 404 ならそのロケーションに無い
```
