import 'package:flutter/material.dart';

import '../../core/reduce_motion.dart';
import '../../core/theme.dart';
import 'culture_models.dart';
import 'culture_parts.dart';
import 'grounding_footer.dart';

/// 「くわしく見る」のポップアップの ✕ ボタン(テストで押すため)。
const cultureSheetCloseKey = ValueKey('culture-sheet-close');

/// カルチャー情報の全項目を、下からせり上がるポップアップで見せる(spec 038 C)。
///
/// ✕・背景のタップ・Esc キー・下へのスワイプで閉じる。
/// 動きを減らす設定のときは、せり上がるアニメーションを行わない(AC-17)。
Future<void> showCultureDetailSheet(
  BuildContext context,
  CultureReport report,
) {
  final reduceMotion = reduceMotionOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    enableDrag: true,
    backgroundColor: Colors.white,
    sheetAnimationStyle: reduceMotion ? AnimationStyle.noAnimation : null,
    builder: (context) => CultureDetailSheet(report: report),
  );
}

/// ポップアップの中身。上部(MV の色)/ 3 つのタブ / 下端に固定の出典と検索候補。
class CultureDetailSheet extends StatelessWidget {
  const CultureDetailSheet({super.key, required this.report});

  final CultureReport report;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fashion = report.fashion;
    final background = report.background;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: DefaultTabController(
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 上部は MV の色(白い文字が読める濃さに調整済み)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [palette.accent, palette.accent2],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'カルチャー情報',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        Text(
                          report.artist,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: cultureSheetCloseKey,
                    tooltip: '閉じる',
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'ファッション'),
                Tab(text: 'MV の衣装'),
                Tab(text: '経歴・音楽性'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _TabBody(
                    children: [
                      if (fashion.isEmpty) const Text('情報が見つかりませんでした'),
                      CultureChips(label: 'スタイル', values: fashion.styles),
                      CultureColors(values: fashion.colors),
                      CultureChips(label: '定番のアイテム', values: fashion.items),
                      CultureParagraph(label: '世界観', text: fashion.worldview),
                      CultureCitations(indices: fashion.sourceIndices),
                    ],
                  ),
                  _TabBody(children: [MvOutfitView(outfit: report.mvOutfit)]),
                  _TabBody(
                    children: [
                      if (background.isEmpty) const Text('情報が見つかりませんでした'),
                      CultureParagraph(label: '概要', text: background.summary),
                      CultureBullets(
                        label: '活動の歩み',
                        values: background.history,
                      ),
                      CultureChips(label: 'ジャンル', values: background.genres),
                      CultureBullets(
                        label: '代表曲',
                        values: background.representativeSongs,
                      ),
                      CultureParagraph(
                        label: '音楽的な特徴',
                        text: background.musicalTraits,
                      ),
                      CultureCitations(indices: background.sourceIndices),
                    ],
                  ),
                ],
              ),
            ),
            // 出典と検索候補は、タブを切り替えても消えないよう下端に固定する(AC-10)
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: GroundingFooter(
                    sources: report.sources,
                    searchSuggestionsHtml: report.searchSuggestionsHtml,
                    webSearchQueries: report.webSearchQueries,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// タブの中身(タブごとに縦にスクロールする)。
class _TabBody extends StatelessWidget {
  const _TabBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
