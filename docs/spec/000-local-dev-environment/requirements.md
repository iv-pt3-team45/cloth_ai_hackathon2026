# 要件定義: ローカル開発環境の整備

- ステータス: reviewed(AC-1 の実機確認待ち)
- 作成日: 2026-09-16
- 更新日: 2026-09-16

## 1. 背景 / 課題

ハッカソン開発を始めるにあたり、フロント(Flutter) / バックエンド(FastAPI) / 外部 API(Gemini on Google Cloud)
を組み合わせた構成をローカルで再現できる土台が無い。以降の機能開発を SPEC 駆動で回すための基盤を先に用意する。

## 2. ゴール / 非ゴール

### ゴール
- `docker compose up` でフロントとバックエンドが同時に起動する。
- バックエンド単体 / フロント単体でもネイティブに起動・テストできる。
- Gemini(Vertex AI)へ疎通するための設定とサンプル実装がある。
- SPEC 駆動開発の運用ルール(spec フォルダ構成)が文書化されている。

### 非ゴール
- 本番デプロイ(Cloud Run 等)の構築。雛形の言及に留める。
- 認証 / 永続化(DB)の導入。必要になった時点で別 spec を切る。

## 3. ユーザーストーリー

- 開発者として、リポジトリを clone した後に最小手順でアプリ全体を起動したい。環境構築で時間を溶かしたくないため。
- 開発者として、機能追加時に参照すべきドキュメントの場所が決まっていてほしい。判断のブレをなくすため。

## 4. 受け入れ基準

- [ ] AC-1: Given リポジトリ直下, When `docker compose up --build`, Then `http://localhost:8080` でフロント、`http://localhost:8000/docs` で API ドキュメントが開ける。(compose 定義の検証済み / 実起動は未確認)
- [x] AC-2: Given `backend/`, When `uv run python -m pytest`, Then 全テストが成功する。
- [x] AC-3: Given `frontend/`, When `flutter analyze` と `flutter test`, Then エラー 0 件で成功する。
- [x] AC-4: Given `.env` に GCP プロジェクトを設定した状態, When メッセージを送信, Then Gemini の応答が返る。(2026-09-17 に実プロジェクトで確認済み)
- [x] AC-6: Given `main` への push, When GitHub Actions が起動, Then Lint / 型チェック / テストが自動実行され、失敗時に検知できる。(ワークフロー作成済み・ローカルで同等コマンドの成功を確認。GitHub 上での初回実行は未確認)
- [x] AC-5: Given `docs/spec/_template/`, When 新機能を開始, Then requirements / design / tasks の雛形をコピーして使える。

## 5. 制約 / 前提

- Gemini は Google Cloud(Vertex AI)経由で利用する。**認証は ADC を基本とする**(鍵ファイルは原則使わない)。
- 型チェック(mypy)は開発マシンのアプリ制御ポリシーで実行できないため、CI での実行を必須とする。
- 開発マシンは Windows 11 を想定(バインドマウントのファイル監視はポーリング)。

## 6. 未決事項

| # | 論点 | 決定者 | 期限 |
| --- | --- | --- | --- |
| 1 | 本番デプロイ先(Cloud Run / GKE) | チーム | 実装機能が固まった後 |
| 2 | 状態管理ライブラリ(Riverpod 等)の導入要否 | チーム | 画面数が増えた時点 |
