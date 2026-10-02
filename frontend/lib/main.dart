import 'package:flutter/material.dart';

import 'features/chat/chat_screen.dart';
import 'features/mv_lookup/mv_lookup_screen.dart';
import 'features/mv_lookup/mv_lookup_snapshot.dart';
import 'features/outfit/confirm_screen.dart';
import 'features/wardrobe/wardrobe_screen.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tx_hackathon_gc',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

/// 機能ごとの画面を下部のナビゲーションで切り替える。
///
/// [IndexedStack] で各画面の状態(入力中の内容や結果)を切り替え後も保つ。
/// MV 検索タブの状態の要約は、ここで受け取って確認タブへ渡す(feature どうしを直接つながない。spec 011)。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _confirmTab = 2;

  int _index = 0;
  final _mvSnapshot = ValueNotifier(const MvLookupSnapshot());

  @override
  void dispose() {
    _mvSnapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          MvLookupScreen(onChanged: (snapshot) => _mvSnapshot.value = snapshot),
          const WardrobeScreen(),
          ConfirmScreen(snapshot: _mvSnapshot, active: _index == _confirmTab),
          const ChatScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.music_video_outlined),
            selectedIcon: Icon(Icons.music_video),
            label: 'MV 検索',
          ),
          NavigationDestination(
            icon: Icon(Icons.checkroom_outlined),
            selectedIcon: Icon(Icons.checkroom),
            label: '手持ちの服',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: '確認',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'チャット',
          ),
        ],
      ),
    );
  }
}
