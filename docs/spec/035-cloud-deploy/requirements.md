# 要件定義: Cloud Run / Firebase への自動デプロイ(F33・F35〜F37)

- ステータス: approved
- 作成日: 2026-10-07
- 更新日: 2026-10-07(決定事項を追記)

## 1. 背景 / 課題

ハッカソンの提出物として、アプリをインターネット上で動かす必要がある。現状は次のとおり。

- backend は、各メンバーが手元から手動で `gcloud run deploy` する運用。環境構築時のテスト用サービスは削除済みで、現在は koushi が 10/5 に手動で作成した `cloth-ai-agent` が `asia-northeast1` にあるが、直近のビルドは失敗している。GitHub の main と、Cloud Run 上で動いているものが一致している保証がない。
- frontend(Flutter Web)は、ローカルと Docker Compose でしか動かしておらず、公開先が無い。
- デプロイ用の環境変数ファイル(`backend/env.deploy.yaml`)が古く、後から追加された機能(MV 検索・カルチャー情報・ライブ情報・コーデ提案・会場情報)の設定が入っていない。
- YouTube Data API は ADC(サービスアカウント)では呼べず API キーが必要だが、Cloud Run 上でキーを安全に渡す仕組みが無い。

機能一覧表の F35(backend の自動デプロイ)・F36(環境変数・IAM)・F37(frontend の自動デプロイ)と、F33(API キー・シークレット管理)のうち Secret Manager の部分を、本 spec で扱う。

## 2. ゴール / 非ゴール

### ゴール
- main にマージされ、既存の CI が通ったら、backend が Cloud Run に自動でデプロイされる(F35)。
- main にマージされ、既存の CI が通ったら、frontend がビルドされ Firebase Hosting に自動でデプロイされる(F37)。Firebase は既存の GCP プロジェクトに追加する。
- GitHub から GCP への認証は Workload Identity 連携で行い、サービスアカウントキー(JSON の鍵ファイル)を作らない・置かない。
- Cloud Run 上で必要な環境変数・IAM ロールを、最小限の権限で設定する(F36)。
- YouTube Data API のキーを Secret Manager で管理し、Cloud Run から読めることを確認する(F33)。キーは Git に入れない。
- ブラウザ(Firebase の URL)から Cloud Run の API を呼べる(CORS を設定する)。
- デプロイに失敗したときに、前のバージョンへ戻す手順がある。
- チームが仕組みと手順を理解できるよう、README 等に記載する。

### 非ゴール
- ステージング環境などの複数環境(本番 1 つだけ)。
- 独自ドメインの設定(Firebase / Cloud Run の既定の URL を使う)。
- API の利用者認証(ログイン)。API は認証なしで公開し、費用は最大インスタンス数などで抑える。
- アプリ本体の機能追加・改修(ただし、デプロイに必要な設定値の追加は含む)。

## 3. ユーザーストーリー

- `開発メンバー` として、`main にマージするだけで最新のアプリが公開される` ようにしたい。なぜなら `手動デプロイの手間と、GitHub と本番のズレを無くしたい` から。
- `審査員・デモの閲覧者` として、`公開 URL を開くだけでアプリを試せる` ようにしたい。なぜなら `手元に環境を作らずに評価したい` から。
- `チーム` として、`API キーなどの秘密情報を Git や GitHub に置かずに運用` したい。なぜなら `漏えいのリスクを避けたい` から。

## 4. 受け入れ基準

- [ ] AC-1: Given 更新した環境変数と IAM 設定, When backend を手動で Cloud Run にデプロイすると, Then `GET /api/v1/health` が 200 を返し、Gemini を使う API(例: `POST /api/v1/venue/lookup`)も Vertex AI 経由で動く(API キーを使わない)。
- [ ] AC-2: Given Secret Manager に YouTube のキーを登録し、実行用のサービスアカウントに読み取り権限を付けた状態, When Cloud Run 上で `POST /api/v1/youtube/lookup` を呼ぶと, Then 動画情報が返る。キーは Git・環境変数ファイル・GitHub のどこにも書かれていない。
- [ ] AC-3: Given main へのマージ, When 既存の CI が成功すると, Then backend が Cloud Run に自動でデプロイされ、新しいリビジョンが動く。
- [ ] AC-4: Given main へのマージ, When 既存の CI が失敗すると, Then デプロイは行われない。
- [ ] AC-5: Given デプロイのワークフロー, When GCP への認証を行うと, Then Workload Identity 連携で認証され、サービスアカウントキーは使われない。対象のリポジトリ(`iv-pt3-team45/cloth_ai_hackathon2026`)の main 以外からは認証できない。
- [ ] AC-6: Given main へのマージ, When 既存の CI が成功すると, Then frontend が Cloud Run の URL を向くようにビルドされ、Firebase Hosting に自動でデプロイされる。
- [ ] AC-7: Given Firebase の URL, When ブラウザで開いて MV 検索 → ライブの選択 → コーデ提案まで操作すると, Then CORS エラーなく Cloud Run の API が呼ばれ、結果が表示される。
- [ ] AC-8: Given デプロイ後に不具合が見つかった状態, When 手順書どおりに操作すると, Then Cloud Run を前のリビジョンに戻せる。
- [ ] AC-9: Given README 等, When チームメンバーが読むと, Then 自動デプロイの流れ・公開 URL・失敗時の確認方法とロールバック手順が分かる。

## 5. 制約 / 前提

- GCP プロジェクト: `ai-agent-hackathon-508804`。Cloud Run のリージョンは `asia-northeast1`。Gemini の location は `global`(東京リージョン指定では新しいモデルが使えないため)。
- Gemini は Vertex AI 経由(ADC / サービスアカウント)で呼ぶ。API キーは YouTube Data API だけ。
- GCP 側の設定(サービスアカウント・Workload Identity 連携・Secret Manager・Firebase の追加)は、清水のオーナー権限で行う。
- GitHub のリポジトリは書き込み権限のみで、管理者権限は無い。そのため GitHub の Secrets / Variables は使わず、秘密ではない値(プロジェクト ID・サービスアカウントのメールアドレス・連携の設定名)はワークフローのファイルに直接書く。
- 既存の CI(`.github/workflows/ci.yml`)はメンバーが作成したもの。デプロイは CI の成功を条件に実行する。
- Firebase Hosting の Cloud Run への転送(rewrites)は 60 秒で打ち切られる。ライブ検索・カルチャー情報・画像生成は 60 秒を超えることがあるため、frontend からは Cloud Run の URL を直接呼ぶ。
- 処理時間: ライブ検索などは最大 120 秒、画像の生成は最大 300 秒(`MEDIA_GENERATION_TIMEOUT`)。Cloud Run のリクエストのタイムアウトはこれより長くする。
- 依存する spec: 000(ローカル開発環境)、007〜011・014(Cloud Run 上で動かす各機能)。

## 6. 決定事項 / 未決事項

### 決定事項(2026-10-07)

| # | 論点 | 決定 |
| --- | --- | --- |
| 1 | デプロイ先の Cloud Run サービス | 既存の `cloth-ai-agent`(`asia-northeast1`。koushi が作成)を本番として使う。自動デプロイで中身と設定を上書きすることを koushi に共有する |
| 2 | 実行用のサービスアカウント | 既定の Compute Engine サービスアカウントを使う(Vertex AI の権限は環境構築時に付与済み)。追加するのは、Secret Manager の YouTube のキー 1 つだけを読む権限のみ |
| 3 | デプロイの処理を書く場所 | 既存の `ci.yml`(メンバーの作成物)とは別のワークフローのファイルにし、CI の成功を条件に動かす |
| 4 | 手持ちの服のデータ | 当面は Cloud Run のサーバー内のファイルに保存する。初期データは GitHub にある内容(保存先は `data/wardrobe/index.json`。現在 0 件)。公開アプリで新しく登録した服は、再デプロイやサーバーの停止で初期状態に戻る。Cloud Storage への移行は後日 F06 の担当が行う想定で、移行時に必要な権限・環境変数の追加はその時点で対応する |
| 5 | 最大インスタンス数 | 当面は 1(サーバーが複数台になると、登録した服が見えなくなるため)。Cloud Storage への移行後に 2〜3 程度へ引き上げる(費用対策として上限は残す) |
| 6 | デモ用のサンプルの服 | 用意しない(GitHub の `tests/` にあるサンプル画像もデプロイされるが、服リストには載せない) |

### 未決事項

| # | 論点 | 決定者 | 期限 |
| --- | --- | --- | --- |
| 1 | 自動デプロイの方式。サポーターから Developer Connect(Cloud Build)の仕組みが共有されているが、本 spec では GitHub Actions を採用する予定(既存の CI の成功を条件にできる、frontend と仕組みを揃えられる、組織への GitHub アプリ導入が不要)。サポーターへの共有・確認 | 清水 | design.md 作成前まで |
| 2 | Cloud Storage への移行の担当とタイミング(上の決定事項 4) | 清水 + F06 担当 | 本番デモ前まで |
