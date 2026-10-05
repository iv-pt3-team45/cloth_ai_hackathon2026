import 'package:flutter/material.dart';

import 'app/home_page.dart';
import 'core/theme.dart';

void main() {
  runApp(const App());
}

/// アプリ全体(テーマとタイトル)。画面は 1 画面の流れ(spec 015)。
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'はじめてのライブ服',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomePage(),
    );
  }
}
