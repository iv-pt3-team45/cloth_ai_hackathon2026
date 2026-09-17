# 要件定義: Agent ADK による Gemini 呼び出し

- ステータス: approved
- 作成日: 2026-09-17
- 更新日: 2026-09-17

## 1. 背景 / 課題

現状のチャット機能は `google-genai` SDK で Gemini を直接呼んでいる(spec 000)。
今後ツール実行やマルチエージェントへ発展させる前提のため、呼び出し基盤を
Google の **Agent Development Kit (ADK)** に載せ替える。まずは最小の呼び出し処理を作る。

## 2. ゴール / 非ゴール

### ゴール
- Gemini の呼び出しを ADK の `LlmAgent` + `Runner` 経由に置き換える。
- 既存の API 契約(`POST /api/v1/chat`)とフロントエンドを変更せずに動くこと。
- ADK 固有の設定(アプリ名・エージェント名・セッション)を設定値として外出しする。

### 非ゴール
- ツール(Function Calling)、マルチエージェント、コールバックの導入。
- セッションのサーバ側永続化(現状はリクエストごとに破棄する)。
- ストリーミング応答。

## 3. ユーザーストーリー

- 開発者として、エージェント機能を足すときに ADK の枠組みにそのまま乗せたい。基盤を作り直したくないため。
- 利用者として、これまでどおりチャット画面でメッセージを送って応答を得たい。

## 4. 受け入れ基準

- [x] AC-1: Given 既存のフロントエンド, When メッセージを送信, Then 変更前と同じ形式(`reply` / `model`)で応答が返る。(2026-09-17 実機確認済み)
- [x] AC-2: Given `history` を含むリクエスト, When 送信, Then 直前までの会話が文脈として Gemini に渡る。(2026-09-17 実機確認済み)
- [x] AC-3: Given `GOOGLE_CLOUD_PROJECT` 未設定, When 送信, Then 502 と設定不備が分かるメッセージが返る。
- [x] AC-4: Given `backend/tests/`, When `uv run python -m pytest`, Then 外部 API を呼ばずに全テストが通る。

## 5. 制約 / 前提

- **認証は ADC(Application Default Credentials)を基本とする。** API キー / サービスアカウントキーは例外扱い。
  Docker 実行時はホストの gcloud 設定ディレクトリをコンテナにマウントする。
- ADK は認証・接続先を**環境変数**(`GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_CLOUD_PROJECT` / `GOOGLE_CLOUD_LOCATION`)から読む。
  本プロジェクトは `.env` を `Settings` に読み込む方式のため、ADK 利用前に `os.environ` へ反映する必要がある。
- セッションは `InMemorySessionService`(プロセス内・再起動で消える)を使う。

## 6. 未決事項

| # | 論点 | 決定者 | 期限 |
| --- | --- | --- | --- |
| 1 | セッションをサーバ側で保持するか(複数インスタンス構成での扱い) | チーム | 会話履歴の永続化に着手する時 |
| 2 | ストリーミング応答の要否 | チーム | UX 検討時 |
