# 設計: ログイン画面とユーザー登録画面

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-10-13

## 1. 設計方針

ログインとユーザー登録を、入力の画面(`HomePage`)の上に重ねる**別の画面**にする。
`Navigator.push` で開き、閉じたら元の画面に戻る。`HomePage` は下に残ったままなので、① ② の入力・選択・取得中の処理は消えない(AC-6)。

ログインの処理は、spec 038 の `AuthSession.login` をそのまま使う。
ログインに成功すると `AuthSession` が変わり、`HomePage._onAuthChanged` が今までどおり服を読み直す。

ユーザー登録の画面は、入力のチェックまで行い、サーバーには送らない(AC-9)。バックエンドは変えない(AC-13)。

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | `Navigator.push(MaterialPageRoute)` で別の画面として重ねる | 採用 | 依存が増えない。`HomePage` の状態が残る。端末の戻る操作・Esc でも閉じられる |
| B | go_router などで `/login`・`/register` の URL を作る | 却下 | 依存の追加が必要(非ゴール)。`HomePage` を作り直すと ① ② の状態が消えるので、状態を外に出す作り直しが要る |
| C | `HomePage` の中で、段階(`Phase`)に「ログイン」を足して出し分ける | 却下 | 入力・進捗・結果の段階とログインの関係が混ざる。ヘッダの段階の表示とも合わない |
| D | ダイアログ / 下から出すシートにする | 却下 | 要件は「専用の画面」。スマホの幅では入力欄とキーボードで窮屈になる |

## 2. 全体フロー

```
HomePage(入力の段階)
  ├─ ヘッダの「ログイン」 ─┐
  └─ ③ の「ログイン」 ─────┴─> openLoginPage(context, session)
                                 │  Navigator.push(LoginPage)
                                 ▼
                         LoginPage「ログイン」
                           ├─ 「ログインする」 → AuthSession.login
                           │      成功 → pop(true) → HomePage(_onAuthChanged が服を読み直す)
                           │      失敗 → 画面に文言(閉じない)
                           ├─ 「ゲストのまま戻る」/ 戻る操作 → pop(false)
                           └─ 「新規登録はこちら」 → push(RegisterPage)
                                                       │
                                                       ▼
                                               RegisterPage「新規登録」
                                                 ├─ 「登録する」 → 入力のチェック
                                                 │      NG → 欄ごとの理由
                                                 │      OK → 受け付けていない旨の案内(送信しない)
                                                 └─ 「ログイン画面へ戻る」/ 戻る操作 → pop
```

## 3. API 設計

変更なし。ログインは spec 038 の `POST /api/v1/auth/login` を使う。登録の API は作らない。

## 4. データモデル

追加なし。入力のチェックの規則だけを、純粋な関数として持つ。

```dart
// features/auth/register_rules.dart
String? userIdProblem(String id);          // null なら OK
String? passwordProblem(String password);
String? confirmProblem(String password, String confirm);
```

| 欄 | 規則 | 文言 |
| --- | --- | --- |
| ユーザー ID | `^[a-z0-9_-]{3,32}$`(`backend/app/services/auth.py` の `USER_ID` と同じ) | 「ユーザー ID は英小文字・数字・_・- の 3〜32 文字にしてください。」(`manage_users.py` と同じ) |
| パスワード | 8 文字以上(`MIN_PASSWORD_LENGTH`) | 「パスワードは 8 文字以上にしてください。」 |
| 確認 | パスワードと一致 | 「確認のパスワードが一致しません。」 |

ユーザー ID は前後の空白を除いてからチェックする。パスワードは除かない(ログインと同じ)。

## 5. フロントエンド設計

### 5.1 ファイル

| ファイル | 変更 |
| --- | --- |
| `features/auth/login_page.dart`(新規) | `LoginPage`。`openLoginPage(context, session)` |
| `features/auth/register_page.dart`(新規) | `RegisterPage` |
| `features/auth/register_rules.dart`(新規) | 入力のチェック(§4) |
| `features/auth/auth_scaffold.dart`(新規) | 2 つの画面の共通の枠(下で説明) |
| `features/auth/login_card.dart` | `LoginCard` を「ゲストの説明 + ログインのボタン」だけにし、`StatelessWidget` にする。入力欄は `LoginPage` に移す。`openRequest` を外し、`onLoginTap` を受け取る。`AccountStatus` は変えない |
| `app/home_page.dart` | `_openLogin` を `openLoginPage` の呼び出しにする。`_loginRequest`・`_wardrobeKey` とスクロールを外す |

### 5.2 画面を開く

```dart
/// ログイン画面を開く。ログインできたら true。
Future<bool> openLoginPage(BuildContext context, AuthSession session) async {
  final theme = Theme.of(context); // MV に合わせた配色(spec 039)を引き継ぐ
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => Theme(data: theme, child: LoginPage(session: session)),
    ),
  );
  return ok ?? false;
}
```

push した画面は、`HomePage` の `AnimatedTheme` の外(Navigator の直下)に出る。
そのため、開くときの `Theme` を包んで渡す(AC-12)。`RegisterPage` は `LoginPage` の中から開くので、同じ `Theme` を引き継ぐ。

### 5.3 共通の枠(`AuthScaffold`)

- `Scaffold` の背景に、`HomePage` と同じグラデーション(`palette.backgroundTop` → `backgroundBottom`)を敷く。背景の動き(`VibeBackdrop`)は出さない。
- 上部の `AppBar`(透明、戻るボタン付き)にタイトル(「ログイン」/「新規登録」)を出す。文字色は `palette.onBackground`。
- 中身は `SingleChildScrollView` に入れる。幅は最大 480px で中央に置き、白いカード(`SectionCard` と同じ見た目)に入れる。スマホの幅とキーボードが出たときにもはみ出さない(AC-12)。

### 5.4 ログイン画面(`LoginPage`)

```
┌ ← ログイン ───────────────────────────┐
│ ┌───────────────────────────────────┐ │
│ │ ユーザー ID とパスワードで             │ │
│ │ ログインすると、登録した服がずっと残ります。│ │
│ │ [ユーザー ID              ]           │ │
│ │ [パスワード             👁]           │ │
│ │ ⚠ ユーザー ID またはパスワードが違います。 │ │
│ │ [ ログインする ]                       │ │
│ │ ─────────────────────                │ │
│ │ アカウントをお持ちでない方 新規登録はこちら │ │
│ │ ゲストのまま戻る                        │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

- 入力欄・ボタン・誤りの扱いは、今の `LoginCard._form` / `_login` を移す(キー `login-user-id` / `login-password`、`ApiException.detail`、「サーバーに接続できませんでした」。AC-3, AC-4, AC-5)。
- ログインに成功したら `Navigator.pop(true)`(AC-2)。「ゲストのまま戻る」は `pop(false)`(AC-6)。
- 送信中は、「新規登録はこちら」「ゲストのまま戻る」・戻るボタンも押せなくする。送信中に閉じて、後から状態が変わるのを防ぐため。戻るボタンは `PopScope(canPop: !_sending)` で止める。

### 5.5 ユーザー登録画面(`RegisterPage`)

```
┌ ← 新規登録 ──────────────────────────┐
│ ┌───────────────────────────────────┐ │
│ │ ⓘ 現在、新規登録は受け付けていません。…  │ │  ← 最初から出す注記(SoftBox)
│ │ [ユーザー ID              ]           │ │
│ │   英小文字・数字・_・- の 3〜32 文字     │ │
│ │ [パスワード             👁]           │ │
│ │   8 文字以上                           │ │
│ │ [パスワード(確認)        👁]           │ │
│ │ [ 登録する ]                           │ │
│ │ ログイン画面へ戻る                      │ │
│ └───────────────────────────────────┘ │
└───────────────────────────────────────┘
```

- 欄ごとのチェックは「登録する」を押したときに行い、`InputDecoration.errorText` に理由を出す(AC-8)。押した後は、入力のたびにその場で更新する。
- すべて OK なら、案内を `MessageBox` で出す(AC-9)。文言は「現在、新規登録は受け付けていません。ログインできるのは運営が登録したユーザーだけです。ゲストのままでも服の登録とコーデの提案を使えます。」。`AuthSession` も `ApiClient` も受け取らないので、サーバーには送らない。
- 最初から出す注記は、AC-9 の文言を短くしたもの:「現在、新規登録は受け付けていません。ログインできるのは運営が登録したユーザーだけです。」(AC-7)
- 「ログイン画面へ戻る」は `Navigator.pop`(AC-10)。

### 5.6 ③ のカード(`LoginCard`)

ゲストの説明(今と同じ文言)と「ログイン」の `FilledButton` だけにする。押すと `onLoginTap`(`HomePage` が `openLoginPage` を呼ぶ)。
ログイン中は出さない。これは今と同じで、`HomePage` が `_auth.isUser` で出し分ける(AC-11)。

### 5.7 `HomePage`

- `_openLogin()` は `openLoginPage(context, _auth)` を呼ぶだけにする。
- 入力の段階以外ではヘッダの「ログイン」を出さない。これは今と同じ(`onLoginTap: _phase == Phase.input ? … : null`)。
- 戻ってきた後の服の読み直し・提案の取り消しは、`_onAuthChanged` で今のまま行う。

## 6. バックエンド設計

変更なし(AC-13)。

## 7. Gemini プロンプト設計

使わない。

## 8. エラーハンドリング / 非機能

- ログインの失敗: 画面を閉じずに、`ErrorText` で理由を出す。文言は spec 038 と同じ。
- 期限切れの知らせ(`AuthSession.notice`): 今どおり `HomePage` の上部に出す。ログインに成功すると `AuthSession` が消す。
- パスワードは画面の外に残さない。`LoginPage` / `RegisterPage` を閉じると、コントローラごと捨てる。
- 動きを減らす設定: 画面の切り替えは `MaterialPageRoute` の標準の動き。Flutter の設定に従う。

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| frontend unit | `register_rules.dart` | `test/register_rules_test.dart`(新規)。境界の値: 2 / 3 / 32 / 33 文字、大文字・記号・全角、パスワード 7 / 8 文字、確認の一致・不一致 |
| frontend widget | ログイン画面・登録画面・③ のカード | `test/login_card_test.dart` を書き直す(`HomePage` を `FakeAuthServer` / `makeSession` で組む)。AC-1〜AC-12 |
| frontend widget | `HomePage` | 既存のテストが通ること(スクロールの処理を外すため) |

`FakeAuthServer` の `/auth/login` 以外へのリクエストの数を数え、登録画面がサーバーに送らないことを確かめる(AC-9)。
`git diff main -- backend/` が空であることを、タスクの最後に確かめる(AC-13)。
