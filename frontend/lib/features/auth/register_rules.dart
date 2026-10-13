// ユーザー登録の画面(spec 040)の入力のチェック。
//
// 規則と文言は、バックエンドのユーザーの追加(services/auth.py の USER_ID・MIN_PASSWORD_LENGTH、
// scripts/manage_users.py の文言)と同じにする。

final _userIdPattern = RegExp(r'^[a-z0-9_-]{3,32}$');

/// パスワードの最小の長さ
const minPasswordLength = 8;

/// ユーザー ID の問題。null なら OK。前後の空白は除いてからチェックする。
String? userIdProblem(String id) => _userIdPattern.hasMatch(id.trim())
    ? null
    : 'ユーザー ID は英小文字・数字・_・- の 3〜32 文字にしてください。';

/// パスワードの問題。null なら OK。空白も文字として数える(ログインと同じ)。
String? passwordProblem(String password) => password.length >= minPasswordLength
    ? null
    : 'パスワードは $minPasswordLength 文字以上にしてください。';

/// 確認のパスワードの問題。null なら OK。
String? confirmProblem(String password, String confirm) =>
    password == confirm ? null : '確認のパスワードが一致しません。';
