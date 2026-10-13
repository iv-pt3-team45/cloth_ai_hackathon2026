import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/auth_session.dart';
import '../../core/widgets.dart';
import 'auth_scaffold.dart';
import 'register_page.dart';

/// ログイン画面を開く(spec 040)。ログインできたら true。
///
/// 入力の画面は下に残したまま重ねるので、閉じても ① ② の入力は残る。
/// 開いた画面は入力の画面の配色(spec 039)の外に出るため、今の [Theme] を包んで渡す。
Future<bool> openLoginPage(BuildContext context, AuthSession session) async {
  final theme = Theme.of(context);
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => Theme(
        data: theme,
        child: LoginPage(session: session),
      ),
    ),
  );
  return ok ?? false;
}

/// ログイン画面(spec 040)。ユーザー ID とパスワードでログインする(spec 038)。
///
/// 成功すると [AuthSession] が変わって画面を閉じる。服の読み直しは入力の画面が行う。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});

  final AuthSession session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userId = TextEditingController();
  final _password = TextEditingController();
  bool _sending = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _userId.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready =>
      _userId.text.trim().isNotEmpty && _password.text.isNotEmpty && !_sending;

  Future<void> _login() async {
    if (!_ready) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.session.login(_userId.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.detail);
    } on Exception {
      if (!mounted) return;
      setState(() => _error = 'サーバーに接続できませんでした');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openRegister() {
    final theme = Theme.of(context);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Theme(data: theme, child: const RegisterPage()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'ログイン',
      canPop: !_sending,
      children: [
        const Text('ログインすると、登録した服がずっと残ります。'),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('login-user-id'),
          controller: _userId,
          autofocus: true,
          enabled: !_sending,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: 'ユーザー ID',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('login-password'),
          controller: _password,
          enabled: !_sending,
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'パスワード',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'パスワードを隠す' : 'パスワードを表示',
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _login(),
        ),
        if (_error != null) ...[const SizedBox(height: 8), ErrorText(_error!)],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _ready ? _login : null,
          child: _sending
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ログインする'),
        ),
        const Divider(height: 32),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Hint('アカウントをお持ちでない方は'),
            TextButton(
              onPressed: _sending ? null : _openRegister,
              child: const Text('新規登録はこちら'),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _sending ? null : () => Navigator.of(context).pop(false),
            child: const Text('ゲストのまま戻る'),
          ),
        ),
      ],
    );
  }
}
