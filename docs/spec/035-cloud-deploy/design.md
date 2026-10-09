# 設計: Cloud Run / Firebase への自動デプロイ(F33・F35〜F37)

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-10-07(T-05 でデプロイ用の権限を追記)

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | GitHub Actions で、CI の成功後に Cloud Run / Firebase へデプロイする。GCP への認証は Workload Identity 連携 | 採用 | 既存の CI の成功を条件にできる。backend と frontend を同じ仕組みで扱える。組織への GitHub アプリの導入(組織の管理者の承認)が不要 |
| B | Developer Connect + Cloud Build のトリガー(サポーター共有の方式) | 却下 | 組織に Google の GitHub アプリを入れる必要がある。GitHub の CI の結果と連動しない(CI が失敗してもデプロイされる)。frontend(Firebase)は別の仕組みが必要になる |
| C | GitHub Actions + サービスアカウントキー(JSON の鍵ファイル)で認証 | 却下 | 鍵が漏れると長期間悪用できる。鍵を置くには GitHub の Secrets(管理者権限)が必要 |

## 2. 全体フロー

```
PR を main にマージ
  └─ GitHub Actions: CI(既存 .github/workflows/ci.yml。backend / frontend / docker の検証)
        └─ 成功したら
           GitHub Actions: Deploy(新規 .github/workflows/deploy.yml)
             ├─ GCP へ認証(Workload Identity 連携。GitHub が発行する短命のトークン → GCP の一時的な権限)
             ├─ backend : gcloud run deploy --source backend  → Cloud Build でビルド → Artifact Registry → Cloud Run(cloth-ai-agent)
             └─ frontend: flutter build web(API_BASE_URL = Cloud Run の URL)→ firebase deploy → Firebase Hosting

ブラウザ ── 画面 ──▶ Firebase Hosting(https://ai-agent-hackathon-508804.web.app)
        └── API ──▶ Cloud Run(https://cloth-ai-agent-872278396120.asia-northeast1.run.app)  ※CORS で Firebase のドメインを許可
                       ├─ Vertex AI(Gemini): 既定の Compute Engine サービスアカウントの権限で呼ぶ
                       └─ YouTube Data API: Secret Manager から読んだキーで呼ぶ
```

- frontend は Cloud Run を直接呼ぶ。Firebase Hosting の Cloud Run への転送(rewrites)は 60 秒で打ち切られ、ライブ検索・画像生成などが間に合わないため使わない。

## 3. API 設計

該当なし(アプリの API は変更しない)。

## 4. データモデル

該当なし。手持ちの服のデータは、当面 Cloud Run のサーバー内のファイル(`data/wardrobe/`)に保存する(requirements.md の決定事項 4)。

## 5. フロントエンド設計

- `frontend/firebase.json`(新規): Hosting の公開フォルダを `build/web` にし、すべてのパスを `index.html` に返す(Flutter Web の画面遷移のため)。
- `frontend/.firebaserc`(新規): 既定のプロジェクトを `ai-agent-hackathon-508804` にする。
- アプリのコードは変更しない。バックエンドの URL はビルド時に `--dart-define=API_BASE_URL=...` で埋め込む(既存の `AppConfig` の仕組み)。

## 6. バックエンド設計

### 6.1 Cloud Run の設定(`cloth-ai-agent`)

| 項目 | 値 | 理由 |
| --- | --- | --- |
| リージョン | `asia-northeast1` | 既存のサービスと同じ |
| ポート | `8000` | Dockerfile が 8000 で待ち受ける(Cloud Run の既定は 8080) |
| 認証 | 認証なしで公開(`--allow-unauthenticated`) | ブラウザから直接呼ぶため |
| 実行用サービスアカウント | `872278396120-compute@developer.gserviceaccount.com`(既定) | 決定事項 2。明示的に指定して、既存の設定に左右されないようにする |
| 最大インスタンス数 | `1` | 決定事項 5(服のデータがサーバーごとに分かれるのを防ぐ・費用対策) |
| 最小インスタンス数 | `0` | アクセスが無いときは費用がかからない(その代わり、最初のアクセスは起動に数秒かかる) |
| リクエストのタイムアウト | `600` 秒 | 画像の生成は最大 300 秒、ライブ検索は最大 120 秒のため、余裕を持たせる |
| メモリ / CPU | `1Gi` / `1` | 画像を扱うため既定(512Mi)より増やす。実測して調整する |
| 環境変数 | `backend/env.deploy.yaml`(6.2) | `--env-vars-file` で渡す。既存の環境変数はすべて置き換わる |
| 秘密情報 | `YOUTUBE_DATA_API_KEY` ← Secret Manager の `youtube-data-api-key:latest` | `--set-secrets` で渡す(6.3) |

### 6.2 環境変数(`backend/env.deploy.yaml` を全面的に書き換え)

本番で既定値から変える必要がある値だけを書く。モデル名などはコード(`app/core/config.py`)の既定値に任せ、二重管理で古くなるのを防ぐ。

| 変数 | 値 | 理由 |
| --- | --- | --- |
| `ENVIRONMENT` | `prod` | ログを JSON 形式にする(Cloud Logging で読みやすくする) |
| `LOG_LEVEL` | `INFO` | |
| `GOOGLE_GENAI_USE_VERTEXAI` | `true` | Gemini を Vertex AI 経由で呼ぶ |
| `GOOGLE_CLOUD_PROJECT` | `ai-agent-hackathon-508804` | |
| `GOOGLE_CLOUD_LOCATION` | `global` | 東京リージョン指定では新しいモデルが使えないため |
| `CORS_ORIGINS` | `["https://ai-agent-hackathon-508804.web.app","https://ai-agent-hackathon-508804.firebaseapp.com"]` | Firebase の画面からの呼び出しを許可する(JSON の形式で書く) |
| `CLOTH_INDEX_PATH` | `data/wardrobe/index.json` | 既定値と同じだが、本番の保存先を明示する(決定事項 4) |
| `IMAGE_DEBUG_LOG` | `false` | 画像生成のプロンプト全文をログに出すデバッグ用の設定。本番ではログが膨らむため止める |

### 6.3 秘密情報(Secret Manager)

- Secret Manager の API を有効化し、シークレット `youtube-data-api-key` を作成して YouTube のキーを登録する。
- 実行用サービスアカウントに、このシークレットだけを対象に `roles/secretmanager.secretAccessor` を付ける(プロジェクト全体には付けない)。
- キーは Git・`env.deploy.yaml`・GitHub のどこにも書かない。登録はコマンドの履歴に残らない方法で行う(tasks.md で手順を示す)。

### 6.4 IAM(最小権限)

**実行用(既定の Compute Engine サービスアカウント)**: 既に付与済みの `roles/aiplatform.user` などに加え、6.3 のシークレットの読み取りだけを追加する。Cloud Build のビルドもこのアカウントで動く(環境構築時に `roles/artifactregistry.writer` などを付与済み)。

**デプロイ用(新規 `github-deployer@ai-agent-hackathon-508804.iam.gserviceaccount.com`)**: GitHub Actions がこのアカウントとして動く。

| ロール | 対象 | 用途 |
| --- | --- | --- |
| `roles/run.developer` | プロジェクト | Cloud Run のサービスを更新する |
| `roles/iam.serviceAccountUser` | 実行用サービスアカウントのみ | 「実行用サービスアカウントで動くサービス」をデプロイする |
| `roles/cloudbuild.builds.editor` | プロジェクト | `--source` のビルドを依頼する |
| `roles/storage.objectAdmin` | バケット `run-sources-ai-agent-hackathon-508804-asia-northeast1` のみ | `--source` でソースコードをアップロードする |
| `roles/storage.legacyBucketReader` | 同上のバケットのみ | アップロード前にバケットの存在を確認する(`objectAdmin` には含まれないため。T-05 で追加) |
| `roles/artifactregistry.reader` | リポジトリ `cloud-run-source-deploy`(`asia-northeast1`)のみ | デプロイ時にイメージの保存先を確認する(T-05 で追加) |
| `roles/storage.bucketViewer` | プロジェクト | `--source` のアップロード前にバケットの一覧を取得する(`storage.buckets.list` はバケット単位では付けられないため。T-11 で追加) |
| `roles/serviceusage.serviceUsageConsumer` | プロジェクト | gcloud / Firebase CLI が API を呼ぶ |
| `roles/firebasehosting.admin` | プロジェクト | Firebase Hosting にデプロイする |

実際に必要な権限が不足していた場合は、エラー内容を見て最小限を追加し、この表を更新する。

### 6.5 Workload Identity 連携

- ワークロード ID プール `github-pool`、プロバイダ `github-provider`(発行元 `https://token.actions.githubusercontent.com`)を作成する。
- 属性の対応付け: `google.subject=assertion.sub`、`attribute.repository=assertion.repository`、`attribute.ref=assertion.ref`。
- **条件**: `assertion.repository == 'iv-pt3-team45/cloth_ai_hackathon2026' && assertion.ref == 'refs/heads/main'`。対象のリポジトリの main 以外からは認証できない(AC-5)。
- デプロイ用サービスアカウントに、上のリポジトリからの成りすましを許可する(`roles/iam.workloadIdentityUser`)。
- ワークフローに書く値(秘密ではない): プロジェクト ID、プロバイダの完全な名前(`projects/872278396120/locations/global/workloadIdentityPools/github-pool/providers/github-provider`)、デプロイ用サービスアカウントのメールアドレス、Cloud Run の URL。

### 6.6 ワークフロー(`.github/workflows/deploy.yml`、新規)

- **起動条件**: `workflow_run`(ワークフロー `CI` が main で完了)かつ成功(`conclusion == 'success'`)かつ push によるもの。あわせて、main で手動実行できるように `workflow_dispatch` も付ける。
- CI が検証したのと同じコミット(`workflow_run.head_sha`)をチェックアウトしてデプロイする。
- 同時に複数のデプロイが走らないよう、`concurrency` で 1 つずつ実行する(途中のデプロイはキャンセルしない)。
- **backend ジョブ**: 認証(`google-github-actions/auth`)→ `gcloud run deploy cloth-ai-agent --source backend ...`(6.1 の設定)→ `GET /api/v1/health` が 200 を返すことを確認する。
- **frontend ジョブ**: backend ジョブの成功後に実行する。Flutter を CI と同じ版(3.41.9)で用意 → `flutter build web --release --dart-define=API_BASE_URL=<Cloud Run の URL>` → 認証 → `firebase deploy --only hosting`。
- 注意: `workflow_run` は、ワークフローのファイルが main に入って初めて動く。そのため、自動デプロイの最初の動作確認は、本ブランチを main にマージした後になる。それまでは同じ設定で手動デプロイして確認する(tasks.md)。

### 6.7 ロールバック

- **backend**: Cloud Run は過去のリビジョンを残しているので、`gcloud run services update-traffic cloth-ai-agent --to-revisions <前のリビジョン>=100` で戻す。原因のコミットは main で revert し、改めて自動デプロイする。
- **frontend**: Firebase コンソールの Hosting のリリース履歴から、前のリリースに戻す。

## 7. Gemini プロンプト設計

該当なし。

## 8. エラーハンドリング / 非機能

- デプロイの失敗: GitHub Actions のログで確認する。backend はヘルスチェックが失敗した時点でワークフローを失敗にし、frontend のデプロイに進まない(画面だけ新しくなり、API が古いままになるのを防ぐ)。
- 費用: 最大インスタンス数 1・最小 0 で上限を設ける。予算アラートはサポーターの担当。
- 起動時間: 最小インスタンス数 0 のため、しばらくアクセスが無いと最初の 1 回は起動に数秒かかる。デモ当日だけ最小インスタンス数を 1 にする運用もできる(README に記載)。
- 組織ポリシー: 会社の GCP で Workload Identity 連携(外部の ID プロバイダ)が組織ポリシーで制限されている場合は作成に失敗する。その場合はサポーターに相談し、案 B(Developer Connect)への切り替えを検討する。
- 既存サービスの設定: `cloth-ai-agent` に以前の環境変数(`YOUTUBE_DATA_API_KEY` を通常の環境変数として設定している等)が残っていると、シークレットへの切り替えで競合することがある。最初の手動デプロイで解消する。

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| 手動 | Cloud Run(手動デプロイ) | `GET /api/v1/health`、`POST /api/v1/venue/lookup`(Gemini)、`POST /api/v1/youtube/lookup`(Secret Manager)を curl で確認(AC-1, AC-2) |
| 手動 | Workload Identity 連携の条件 | main 以外のブランチからは認証できないことを確認(AC-5) |
| 手動 | 自動デプロイ | main へのマージ後に、Deploy ワークフローの成功、Cloud Run の新しいリビジョン、Firebase の新しいリリースを確認(AC-3, AC-6) |
| 手動 | CI 失敗時 | CI が失敗した場合に Deploy が動かないことを確認(AC-4) |
| 手動 | 通し | Firebase の URL から MV 検索 → ライブの選択 → コーデ提案(AC-7) |
| 手動 | ロールバック | 前のリビジョンへ戻せることを確認(AC-8) |
