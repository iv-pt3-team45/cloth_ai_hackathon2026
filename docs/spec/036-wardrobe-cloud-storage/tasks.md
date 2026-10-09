# タスク: 手持ちの服の Cloud Storage への保存(F06)

- 対応する設計: `./design.md`
- 更新日: 2026-10-08

## タスク

### 準備

- [x] T-1: `uv add google-cloud-storage` で依存を追加する。`config.py` と `backend/.env.example` に `WARDROBE_STORAGE` / `WARDROBE_GCS_BUCKET` / `WARDROBE_GCS_PREFIX` を追加する(design 4.1)
  - 完了条件: 既存の pytest が通る

### 保存先の実装

- [x] T-2: `wardrobe_store.py` の `index.json` の組み立て・読み取りと、服 1 点を消す処理を共通の関数に切り出し、`create_wardrobe_store(settings)` を追加する(design 6.1・6.2)
  - 完了条件: ローカルの既存テストが変更なしで通る。切り替えのテストを追加(AC-1)
- [x] T-3: `wardrobe_gcs.py` に `GcsWardrobeStore` を作る(保存・一覧・削除・写真の読み出し・例外の変換。design 6.3)。テスト用のバケットの偽物 `tests/gcs_stub.py` を作る
  - 完了条件: 偽物を使ったテストで、保存・一覧・削除・写真の読み出し・失敗時(AC-2〜AC-4・AC-6)が通る
- [x] T-4: 条件付きの書き込みとやり直し(design 6.4)
  - 完了条件: 同時書き込みのテストで、両方の登録が残る(AC-7)

### 呼び出し側の切り替え

- [x] T-5: `WardrobeService`・`routes/wardrobe.py`・`OutfitService` を `create_wardrobe_store` に切り替え、保存先の失敗を 502 にする(design 3・6.1)
  - 完了条件: spec 010 / 011 の既存テストが通る。502 になる API のテストを追加(AC-6)
- [x] T-6: エージェントのツール(`wardrobe.py`)を保存先経由にし、CLI の `--index` でローカルに固定する(design 6.5)
  - 完了条件: 偽物のバケットでツールが登録した服を返すテスト、既存の spec 006 のテストが通る(AC-9〜AC-11)

### GCP の設定と動作確認(Claude が実行。実行前にコマンドを提示して承認を得る)

- [x] T-7: バケットを作り、Cloud Run のサービスアカウントに権限を付ける(design 8.1)
  - 完了条件: `gcloud storage buckets describe` で非公開・東京リージョンを確認(AC-8)
  - 結果(2026-10-08): 作成・権限の付与とも完了(編集者の権限で付与できた)。認証なしの取得は 403
- [ ] T-8: ローカルで `WARDROBE_STORAGE=gcs` にして手動で確認する。画面から登録・一覧・提案・削除 → CLI のエージェントに手持ちの服を聞く → 再起動して残っていること
  - 完了条件: AC-2〜AC-5・AC-9 を実際のバケットで確認
  - 途中経過(2026-10-08): 保存・一覧・写真の読み出し・削除(別のインスタンスからの読み直しを含む)と、CLI のエージェントがバケットから服を読んで答えること、`--index` でローカルを読むことを確認済み。確認用の服は削除済み。
  - 途中経過(2026-10-08 追記): ローカルでバックエンドを `WARDROBE_STORAGE=gcs` で起動し、API(画面と同じ流れ: 解析 → 保存 → 一覧 → 写真の表示 → 削除)でバケットに保存されること、`data/wardrobe/` が作られないこと、サーバーを再起動しても一覧に残ることを確認済み。この PC には Flutter が無いため、**画面からの登録・コーデ提案の確認は、マージ後に本番の画面で行う**(AC-3・AC-5)
  - 途中経過(2026-10-09): PR #14 のマージ後、本番(Cloud Run リビジョン cloth-ai-agent-00009-g2f。WARDROBE_STORAGE=gcs)の画面から服を 1 枚登録し、バケットの wardrobe/images/ と index.json に保存されたことを確認(AC-2・AC-3 の登録・一覧)。**コーデ提案と、再デプロイ後に残ること(AC-5)は未確認**

### デプロイ設定とドキュメント

- [x] T-9: `env.deploy.yaml` に `WARDROBE_STORAGE: 'gcs'` と `WARDROBE_GCS_BUCKET` を追加する
  - 完了条件: マージ後の本番で、登録した服が再デプロイ後も残る(AC-5。本番の確認はマージ後)
- [x] T-10: README を更新する(技術スタック・構成図・ディレクトリ構成・環境変数・保存先の切り替えとバケットの作り方・4.13 の注意点・機能一覧・トラブルシューティング)
  - 完了条件: AC-12
- [x] T-11: 検証コマンド(pytest / ruff check / ruff format)を通し、requirements の AC にチェックを付ける
