# タスク: ユーザーのログインと、手持ちの服のユーザーごとの紐づけ

- 対応する設計: `./design.md`
- 更新日: 2026-10-09

## タスク

### バックエンド: ログインの土台

- [x] T-1: `uv add pyjwt`。`config.py` と `.env.example` に `AUTH_SECRET_KEY` / `AUTH_TOKEN_DAYS` / `GUEST_WARDROBE_HOURS` を追加する(design 4.4)
  - 完了条件: 既存の pytest が通る
- [x] T-2: `services/auth.py` に `Owner`、パスワードのハッシュ・照合、トークンの発行・確認を作る(design 4.1・6.2)
  - 完了条件: 期限切れ・改ざん・種類違い・不正な `sub` が `InvalidTokenError` になるテスト(AC-3・AC-10)
- [x] T-3: `services/user_store.py` にユーザーの保存先(local / gcs)を作り、`AuthService`(ログイン・ゲスト・トークンの確認)を作る(design 4.2・6.1)
  - 完了条件: 追加・削除・パスワード変更がすぐ反映される、削除したユーザーのトークンが使えないテスト(AC-1〜AC-3・AC-15)
- [x] T-4: `schemas/auth.py`・`routes/auth.py`(login / guest / me)・`api/deps.py` の `current_owner` を作り、`router.py` に登録する(design 3.1〜3.3)
  - 完了条件: API のテスト(成功・401・422・鍵が未設定の 503)

### バックエンド: 持ち主ごとの保存先

- [x] T-5: `create_wardrobe_store(settings, owner)` で持ち主ごとの置き場所にし、ゲストは `GUEST_WARDROBE_HOURS` より古い服を読まない(design 2.3・6.1)
  - 完了条件: local / gcs の両方で置き場所が分かれるテスト、ゲストの期限のテスト(AC-7・AC-9)
- [x] T-6: `WardrobeService`・`OutfitService` に持ち主を渡し、`routes/wardrobe.py`・`routes/outfit.py` で `current_owner` を必須にする(analyze 以外。design 3.4)
  - 完了条件: 既存の API テストが(`current_owner` を差し替えて)通る。ユーザー A / B / ゲストの分離と 401 のテスト(AC-5・AC-8・AC-10)

### バックエンド: 運営のコマンドと CLI

- [x] T-7: `scripts/manage_users.py`(add / delete / passwd / list、`--generate`)を作る(design 6.1)
  - 完了条件: 一時フォルダでのテスト。パスワードが引数に出ない(AC-15)
- [x] T-8: `run_agent.py` / `run_agent_loop.py` に `--user` を足す
  - 完了条件: 指定したユーザーの服をツールが返すテスト(AC-16)

### フロントエンド

- [x] T-9: `shared_preferences` を追加し、`core/auth_session.dart`(保存・読み込み・ゲストのトークン・ログイン・ログアウト)と `features/auth/auth_repository.dart` を作る(design 2.1・4.5・5.1)
  - 完了条件: 起動時の 3 通り(ユーザー / ゲスト / 無し・期限切れ)のテスト(AC-11)
- [x] T-10: `api_client.dart` でトークンを付け、401 の扱い(ユーザー → ゲストに戻す、ゲスト → 取り直して 1 回やり直す)を入れる(design 2.2)
  - 完了条件: 401 のテスト(AC-10)
- [x] T-11: 写真の表示をバイト列の取得に変える(`imageBytes` とキャッシュ、`ClothPhoto` と提案の画面。design 5.3)
  - 完了条件: 写真の表示のテスト(AC-13)
- [x] T-12: ログインのカード(③ の中)とヘッダの表示、ログイン・ログアウトで一覧を読み直す処理(design 5.2)
  - 完了条件: ログイン成功・失敗・ログアウトの画面のテスト(AC-1・AC-2・AC-12・AC-14)

### GCP の設定・デプロイ・ドキュメント(GCP の操作は実行前にコマンドを提示して承認を得る)

- [ ] T-13: ゲストの服のライフサイクルルール、`auth-secret-key` の作成と権限の付与、`deploy.yml` の `--set-secrets` の追加(design 6.3)
  - 完了条件: `gcloud storage buckets describe` でルールを確認(AC-7)。権限の付与ができなければ清水に依頼
  - 途中経過(2026-10-09): ライフサイクルルール(guests/ を作成から 1 日で削除)と `auth-secret-key`(バージョン 1)は作成済み。`deploy.yml` も変更済み。**Cloud Run の実行用サービスアカウントへの読み取り権限の付与は、編集者の権限では 403 のため清水に依頼中**
- [x] T-14: ローカルで手動で確認する(ログイン・ゲスト・再読み込み・ユーザーの分離)。この PC には Flutter が無いため、API での確認とし、画面はマージ後に本番で確認する
  - 結果(2026-10-09): ローカル(`WARDROBE_STORAGE=local`)で API を確認(ログインの成功・失敗、401、ユーザー / ゲスト / 別のゲストの分離、他の人の写真・削除が 404、置き場所の分離)。Flutter を入れたため、画面もローカルで和佐田が確認済み
- [x] T-15: 本番のバケットに `demo01`〜`demo05` を作り、パスワードを和佐田に渡す(Git・spec には書かない)
- [x] T-16: README を更新する(技術スタック・構成図・ディレクトリ構成・環境変数・ログインとゲストの仕組み・ユーザーの追加方法・API・機能一覧・トラブルシューティング)
  - 完了条件: AC-19
- [x] T-17: 検証コマンド(pytest / ruff / mypy / dart format / flutter analyze / flutter test)を通し、requirements の AC にチェックを付ける(2026-10-09: Flutter をこの PC に入れたため、すべてローカルで実行。AC-7 は本番で 1 日たってから確認)
