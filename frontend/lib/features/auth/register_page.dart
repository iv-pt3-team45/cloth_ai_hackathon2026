import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'auth_scaffold.dart';
import 'register_rules.dart';

/// 登録を受け付けていないことの注記(最初から出す)
const registerClosedNote = '現在、新規登録は受け付けていません。ログインできるのは運営が登録したユーザーだけです。';

/// 正しく入力して「登録する」を押したときの案内
const registerClosedMessage = '$registerClosedNoteゲストのままでも服の登録とコーデの提案を使えます。';

/// ユーザー登録画面(spec 040)。画面だけで、サーバーには送らない。
///
/// 入力のチェック(register_rules.dart)まで行い、正しければ受け付けていないことを案内する。
/// サーバーにつなぐ部品([AuthSession] など)を受け取らないので、送ることはできない。
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _userId = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPassword = false;

  /// 一度「登録する」を押したら、入力のたびに理由を更新する
  bool _attempted = false;
  bool _accepted = false;

  @override
  void dispose() {
    _userId.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? get _userIdError => _attempted ? userIdProblem(_userId.text) : null;
  String? get _passwordError =>
      _attempted ? passwordProblem(_password.text) : null;
  String? get _confirmError =>
      _attempted ? confirmProblem(_password.text, _confirm.text) : null;

  void _changed() => setState(() => _accepted = false);

  void _submit() {
    setState(() {
      _attempted = true;
      _accepted =
          userIdProblem(_userId.text) == null &&
          passwordProblem(_password.text) == null &&
          confirmProblem(_password.text, _confirm.text) == null;
    });
  }

  InputDecoration _decoration(String label, {String? helper, String? error}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: error,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      );

  Widget _eye() => IconButton(
    tooltip: _showPassword ? 'パスワードを隠す' : 'パスワードを表示',
    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
    onPressed: () => setState(() => _showPassword = !_showPassword),
  );

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: '新規登録',
      children: [
        const SoftBox(
          margin: EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppColors.muted,
                ),
              ),
              SizedBox(width: 8),
              Expanded(child: Text(registerClosedNote)),
            ],
          ),
        ),
        TextField(
          key: const ValueKey('register-user-id'),
          controller: _userId,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newUsername],
          decoration: _decoration(
            'ユーザー ID',
            helper: '英小文字・数字・_・- の 3〜32 文字',
            error: _userIdError,
          ),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('register-password'),
          controller: _password,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          decoration: _decoration(
            'パスワード',
            helper: '$minPasswordLength 文字以上',
            error: _passwordError,
          ).copyWith(suffixIcon: _eye()),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('register-confirm'),
          controller: _confirm,
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.newPassword],
          decoration: _decoration(
            'パスワード(確認)',
            error: _confirmError,
          ).copyWith(suffixIcon: _eye()),
          onChanged: (_) => _changed(),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        if (_accepted)
          MessageBox(
            color: AppPalette.of(context).accent,
            children: const [Text(registerClosedMessage)],
          ),
        FilledButton(onPressed: _submit, child: const Text('登録する')),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ログイン画面へ戻る'),
          ),
        ),
      ],
    );
  }
}
