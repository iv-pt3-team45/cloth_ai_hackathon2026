import 'package:flutter/material.dart';

/// 今の配色のまま、別の画面を重ねて開く(spec 041)。
///
/// `Navigator.push` で開いた画面は入力の画面の `AnimatedTheme`(MV の配色。spec 039)の外に出るため、
/// 開く側の [Theme] を包んで渡す。ダイアログ・シートは Flutter が自動で引き継ぐので使わなくてよい。
Future<T?> pushThemed<T>(BuildContext context, WidgetBuilder builder) {
  final theme = Theme.of(context);
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (routeContext) => Theme(
        data: theme,
        child: Builder(builder: builder),
      ),
    ),
  );
}
