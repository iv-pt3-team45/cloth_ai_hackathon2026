# 実装タスク: ログイン画面とユーザー登録画面

- 対応する設計: `./design.md`
- 進捗: 6 / 6

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 完了したら `- [ ]` を `- [x]` にする。
- フロントエンドの完了条件は、特記が無ければ `dart format .` / `flutter analyze`(警告なし)/ `flutter test` が通ること。

## タスク一覧

### バックエンド

変更なし(AC-13)。

### フロントエンド

- [x] **T-01: 入力のチェック(`register_rules.dart`)**
  - 変更対象: `frontend/lib/features/auth/register_rules.dart`(新規), `frontend/test/register_rules_test.dart`(新規)
  - 完了条件: design §4 の規則と文言で判定できる。境界の値のテストが通る:
    ID が 2 / 3 / 32 / 33 文字、大文字・記号・全角、前後の空白、パスワードが 7 / 8 文字、確認の一致・不一致
  - 関連 AC: AC-8
- [x] **T-02: 共通の枠(`AuthScaffold`)とログイン画面(`LoginPage`・`openLoginPage`)**
  - 変更対象: `features/auth/auth_scaffold.dart`(新規), `features/auth/login_page.dart`(新規)
  - 完了条件: `LoginCard` の入力欄・ログインの処理を移す。
    成功で `pop(true)`、「ゲストのまま戻る」で `pop(false)`、送信中は戻れない。開いたときの配色を引き継ぐ
  - 関連 AC: AC-1, AC-2, AC-3, AC-4, AC-5, AC-12
- [x] **T-03: ユーザー登録画面(`RegisterPage`)**
  - 変更対象: `features/auth/register_page.dart`(新規), `features/auth/login_page.dart`(「新規登録はこちら」)
  - 完了条件: 最初から注記が出る。「登録する」で欄ごとに理由が出て、OK なら案内が出る(送信しない)。「ログイン画面へ戻る」で戻る
  - 関連 AC: AC-7, AC-8, AC-9, AC-10
- [x] **T-04: ③ のカードと `HomePage` のつなぎ替え**
  - 変更対象: `features/auth/login_card.dart`, `app/home_page.dart`
  - 完了条件: `LoginCard` を説明 + ボタンだけにする(`openRequest` を外し、`onLoginTap` を受け取る)。
    ヘッダ・③ の「ログイン」で `openLoginPage` を開く。`_loginRequest`・`_wardrobeKey` のスクロールを外す
  - 関連 AC: AC-1, AC-6, AC-11
- [x] **T-05: 画面のテスト**
  - 変更対象: `frontend/test/login_card_test.dart`(書き直す)
  - 完了条件: AC-1〜AC-12 のテストが通る。特に次を確かめる:
    - ① ② の入力が残る
    - 登録画面がサーバーに送らない(`FakeAuthServer` へのリクエストの数が増えない)
    - 390px の幅でどの画面もはみ出さない
    - 暗い配色を引き継ぐ

    既存のテスト(`home_page_test.dart` など)も通る
  - 関連 AC: AC-1〜AC-12

### 結合 / 仕上げ

- [x] **T-06: ドキュメント更新**(2026-10-13: デモでの画面の確認は行わない。ユーザーがマージの後に確認する)
  - 変更対象: `README.md`(§2.4・§3.6・§4・§6), `requirements.md`
  - 完了条件:
    - (画面の確認はマージの後にユーザーが行うため、このタスクには含めない)
    - README を更新する。§3.6 の「ユーザー登録の画面は無い」を直し、ログイン画面の説明を足す。§6 に 040 の行を足す。
    - `git diff --stat main -- backend/` が空であることを確かめ、`requirements.md` を `done` にする
  - 関連 AC: AC-12, AC-13
