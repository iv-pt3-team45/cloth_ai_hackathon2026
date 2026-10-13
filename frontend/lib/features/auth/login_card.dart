import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/auth_session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// ゲストのときに「③ 手持ちの服」の上部に出す案内とログインの入力欄(spec 038)。
///
/// 最初は案内と「ログイン」だけを出し、押すとユーザー ID とパスワードの入力欄が開く。
/// ログインに成功すると [AuthSession] が変わり、画面がログイン中の表示に切り替わる。
class LoginCard extends StatefulWidget {
  const LoginCard({super.key, required this.session, this.openRequest = 0});

  final AuthSession session;

  /// 増えるたびに入力欄を開く(ヘッダの「ログイン」から開くため)
  final int openRequest;

  @override
  State<LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<LoginCard> {
  final _userId = TextEditingController();
  final _password = TextEditingController();
  bool _open = false;
  bool _sending = false;
  bool _showPassword = false;
  String? _error;

  @override
  void didUpdateWidget(LoginCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openRequest != oldWidget.openRequest) {
      setState(() => _open = true);
    }
  }

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

  void _close() {
    setState(() {
      _open = false;
      _error = null;
      _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SoftBox(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'ゲストとして使っています。登録した服は 1 日で消えます。'
                  'ログインすると、ずっと残せます。',
                ),
              ),
              if (!_open) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => setState(() => _open = true),
                  child: const Text('ログイン'),
                ),
              ],
            ],
          ),
          if (_open) ..._form(),
        ],
      ),
    );
  }

  List<Widget> _form() => [
    const SizedBox(height: 12),
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
          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _login(),
    ),
    if (_error != null) ...[const SizedBox(height: 8), ErrorText(_error!)],
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: _ready ? _login : null,
          child: _sending
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ログインする'),
        ),
        TextButton(
          onPressed: _sending ? null : _close,
          child: const Text('やめる'),
        ),
      ],
    ),
  ];
}

/// ヘッダの右側に出す、ログイン中のユーザー名とログアウト(ゲストなら「ゲスト」)(spec 038)。
class AccountStatus extends StatelessWidget {
  const AccountStatus({super.key, required this.session, this.onLoginTap});

  final AuthSession session;

  /// ゲストのときの「ログイン」を押したとき(③ のカードへ案内する)
  final VoidCallback? onLoginTap;

  @override
  Widget build(BuildContext context) {
    // カードの外(ヘッダ)に出すので、暗い背景(spec 039)では白系の文字にする
    final palette = AppPalette.of(context);
    final button = palette.dark
        ? TextButton.styleFrom(foregroundColor: palette.onBackground)
        : null;
    final userId = session.userId;
    if (userId == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ゲスト', style: TextStyle(color: palette.onBackgroundMuted)),
          if (onLoginTap != null)
            TextButton(
              style: button,
              onPressed: onLoginTap,
              child: const Text('ログイン'),
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.person, size: 18, color: palette.onBackgroundMuted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            userId,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: palette.onBackground,
            ),
          ),
        ),
        TextButton(
          style: button,
          onPressed: session.logout,
          child: const Text('ログアウト'),
        ),
      ],
    );
  }
}
