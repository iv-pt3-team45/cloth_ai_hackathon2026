import 'package:flutter/material.dart';

import '../../core/auth_session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// ゲストのときに「③ 手持ちの服」の上部に出す案内(spec 038 / 040)。
///
/// ゲストの説明と「ログイン」だけを出す。ログインの入力欄はログイン画面(login_page.dart)にある。
class LoginCard extends StatelessWidget {
  const LoginCard({super.key, required this.onLoginTap});

  /// 「ログイン」を押したとき(ログイン画面を開く)
  final VoidCallback onLoginTap;

  @override
  Widget build(BuildContext context) {
    return SoftBox(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline, size: 18, color: AppColors.muted),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'ゲストとして使っています。登録した服は 1 日で消えます。'
              'ログインすると、ずっと残せます。',
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onLoginTap, child: const Text('ログイン')),
        ],
      ),
    );
  }
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
