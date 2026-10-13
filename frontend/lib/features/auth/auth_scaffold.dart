import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

/// ログイン画面・ユーザー登録画面(spec 040)の共通の枠。
///
/// 入力の画面と同じ背景のグラデーションを敷き、中身を幅 480px までの白いカードに入れる。
/// 配色は開いたときの [Theme](MV に合わせた配色。spec 039)に従う。
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.children,
    this.canPop = true,
  });

  /// 上部に出す画面の名前
  final String title;
  final List<Widget> children;

  /// false の間は、戻るボタン・端末の戻る操作で閉じない(ログインの送信中)
  final bool canPop;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PopScope(
      canPop: canPop,
      child: PaletteBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: palette.onBackground,
            automaticallyImplyLeading: false,
            leading: canPop ? const BackButton() : null,
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: palette.onBackground,
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SectionCard(children: children),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
