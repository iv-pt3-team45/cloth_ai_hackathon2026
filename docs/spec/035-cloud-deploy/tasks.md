# 実装タスク: Cloud Run / Firebase への自動デプロイ(F33・F35〜F37)

- 対応する設計: `./design.md`
- 進捗: 4 / 14

## 凡例

- 1 タスク = 30〜90 分。確認まで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 【清水】は清水が自分の環境で実行する作業(GCP の設定・gcloud・git)。【Claude】はファイルの作成・修正(方針を説明してから行う)。
- PowerShell では `gcloud` の代わりに `gcloud.cmd` を使う(実行ポリシーの制限のため)。
- 完了したら `- [ ]` を `- [x]` にする。

## タスク一覧

### フェーズ 1: 手動で Cloud Run に正しくデプロイできる状態にする(F36・F33)

- [x] **T-01: 必要な API の有効化を確認する**【清水】
  - 内容: Cloud Run・Cloud Build・Artifact Registry・Vertex AI・YouTube Data API v3・Secret Manager・IAM Credentials・Security Token Service・Firebase Hosting の API が有効か確認し、無効なものを有効化する
  - 完了条件: `gcloud.cmd services list --enabled` に上記がすべて出る
  - 関連 AC: -(準備)

- [x] **T-02: Secret Manager に YouTube のキーを登録する**【清水】
  - 内容: シークレット `youtube-data-api-key` を作成してキーを登録し、実行用サービスアカウント(`872278396120-compute@developer.gserviceaccount.com`)に、このシークレットだけの `roles/secretmanager.secretAccessor` を付ける。キーがコマンドの履歴や画面に残らない方法で登録する
  - 完了条件: `gcloud.cmd secrets versions list youtube-data-api-key` にバージョンが 1 つ表示され、シークレットの IAM に実行用サービスアカウントが入っている
  - 関連 AC: AC-2

- [x] **T-03: `backend/env.deploy.yaml` を書き直す**【Claude】
  - 内容: design.md 6.2 の 8 項目だけにする(モデル名などはコードの既定値に任せる)
  - 完了条件: ファイルに秘密情報が含まれず、design.md 6.2 と一致している
  - 関連 AC: AC-1

- [x] **T-04: `cloth-ai-agent` に手動でデプロイして動作を確認する**【清水】
  - 内容: design.md 6.1 の設定で `gcloud.cmd run deploy cloth-ai-agent --source backend ...` を実行する。koushi の直近のビルドが失敗していた原因が解消していることも確認する
  - 完了条件: Cloud Run の URL で `GET /api/v1/health` が 200、`POST /api/v1/venue/lookup`(Gemini)と `POST /api/v1/youtube/lookup`(Secret Manager のキー)が結果を返す
  - 実施メモ(2026-10-07): `backend/.gcloudignore` が無く `.env` まで送られかねなかったため追加した。ビルドは `backend/Dockerfile` の `RUN --mount=type=cache` が Cloud Build の既定のビルド方式で使えず失敗したため、`--mount` を外した(koushi の以前のビルド失敗も同じ原因)
  - 関連 AC: AC-1, AC-2

### フェーズ 2: backend の自動デプロイ(F35)

- [ ] **T-05: デプロイ用サービスアカウントを作成する**【清水】
  - 内容: `github-deployer` を作成し、design.md 6.4 のロールを付ける(`iam.serviceAccountUser` は実行用サービスアカウントだけ、`storage.objectAdmin` はソースのアップロード先のバケットだけを対象にする)
  - 完了条件: `gcloud.cmd projects get-iam-policy` 等で、design.md 6.4 のとおりに付いている
  - 関連 AC: AC-3

- [ ] **T-06: Workload Identity 連携を設定する**【清水】
  - 内容: プール `github-pool`・プロバイダ `github-provider` を作成し、リポジトリと main ブランチの条件を付ける。`github-deployer` に、このリポジトリからの成りすましを許可する
  - 完了条件: プロバイダの条件が design.md 6.5 と一致している。組織ポリシーで作成できない場合は、ここで止めてサポーターに相談する
  - 関連 AC: AC-5

- [ ] **T-07: `deploy.yml`(backend ジョブ)を作成する**【Claude】
  - 変更対象: `.github/workflows/deploy.yml`(新規)
  - 内容: design.md 6.6 のとおり、CI の成功後(と手動実行)に、認証 → `gcloud run deploy` → ヘルスチェックを行う
  - 完了条件: ワークフローのファイルが構文的に正しい(GitHub の画面でエラーが出ない)。実際の動作確認は T-11
  - 関連 AC: AC-3, AC-4, AC-5

### フェーズ 3: frontend の Firebase デプロイ(F37)

- [ ] **T-08: 既存の GCP プロジェクトに Firebase を追加する**【清水】
  - 内容: Firebase コンソールで `ai-agent-hackathon-508804` を選んで Firebase を追加し、Hosting を有効にする
  - 完了条件: Hosting の既定のサイト(`ai-agent-hackathon-508804.web.app`)が作られている
  - 関連 AC: AC-6

- [ ] **T-09: `firebase.json` / `.firebaserc` を作成する**【Claude】
  - 変更対象: `frontend/firebase.json`、`frontend/.firebaserc`(新規)
  - 内容: design.md 5 のとおり。手元に Node.js があれば、一度手動で `firebase deploy` して画面が出ることを確認する(無ければ T-11 で確認する)
  - 完了条件: ファイルが作成されている。手動で確認できた場合は Firebase の URL で画面が表示される
  - 関連 AC: AC-6

- [ ] **T-10: `deploy.yml` に frontend ジョブを追加する**【Claude】
  - 内容: backend ジョブの成功後に、Flutter のビルド(`API_BASE_URL` = Cloud Run の URL)→ 認証 → `firebase deploy --only hosting` を行う
  - 完了条件: ワークフローのファイルが構文的に正しい。実際の動作確認は T-11
  - 関連 AC: AC-6

### フェーズ 4: 通しの確認と仕上げ

- [ ] **T-11: PR を作成・マージし、自動デプロイを確認する**【清水】
  - 内容: PR のマージ後、CI → Deploy の順に動き、Cloud Run の新しいリビジョンと Firebase の新しいリリースができることを確認する。Deploy の条件(CI が失敗したら動かない・main 以外では認証できない)も、ワークフローとプロバイダの設定で確認する
  - 完了条件: Deploy ワークフローが成功する
  - 関連 AC: AC-3, AC-4, AC-5, AC-6

- [ ] **T-12: Firebase の URL から通しで確認する**【清水】
  - 内容: Firebase の URL で、MV 検索 → ライブの選択 → コーデ提案まで操作する
  - 完了条件: CORS エラーなく結果が表示される
  - 関連 AC: AC-7

- [ ] **T-13: ロールバックを試す**【清水】
  - 内容: Cloud Run を前のリビジョンへ戻し、元に戻す。Firebase のリリース履歴の場所も確認する
  - 完了条件: 手順どおりに戻せる
  - 関連 AC: AC-8

- [ ] **T-14: README を更新する**【Claude】
  - 変更対象: `README.md`
  - 内容: 自動デプロイの流れ、公開 URL、失敗時の確認方法、ロールバック手順、デモ当日に最小インスタンス数を 1 にする方法を書く
  - 完了条件: チームメンバーが README だけで流れと対処が分かる
  - 関連 AC: AC-9
