import 'package:flutter/material.dart';

import '../../core/reduce_motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'culture_detail_sheet.dart';
import 'culture_models.dart';
import 'culture_parts.dart';
import 'grounding_footer.dart';

/// 動画のアーティストのカルチャー情報(spec 008)を表示する。
///
/// 取得の開始と入力のロックは [MvLookupPanel] が行い、ここは状態に応じた表示だけを担う。
/// 調べている途中・失敗・特定できないときは薄い茶の枠(spec 015)、届いたら要点のカード(spec 038)。
class CultureSection extends StatelessWidget {
  const CultureSection({
    super.key,
    required this.loading,
    required this.onRetry,
    this.report,
    this.error,
  });

  final bool loading;
  final CultureReport? report;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final report = this.report;
    final Widget child;
    if (loading) {
      child = const _Loading();
    } else if (error != null) {
      child = _Failure(message: error!, onRetry: onRetry);
    } else if (report == null) {
      return const SizedBox.shrink();
    } else if (!report.identified) {
      child = _Unidentified(report: report);
    } else {
      // 動画が変わったら出現のアニメーションをやり直す
      return CultureSummaryCard(key: ObjectKey(report), report: report);
    }
    return SoftBox(child: child);
  }
}

/// カルチャー情報の要点のカード(spec 038 C)。
///
/// アーティスト名・スタイル・よく使う色・この MV の衣装・出典・検索候補を出し、
/// 全項目は「くわしく見る」のポップアップで見せる。現れるときは弾むように出て、中の項目が順に浮かび上がる。
class CultureSummaryCard extends StatefulWidget {
  const CultureSummaryCard({super.key, required this.report});

  final CultureReport report;

  @override
  State<CultureSummaryCard> createState() => _CultureSummaryCardState();
}

class _CultureSummaryCardState extends State<CultureSummaryCard>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 動きを減らす設定では最初から表示済みにする(AC-17)
    if (reduceMotionOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// [index] 番目の項目を、少しずつ遅らせて下から浮かび上がらせる
  Widget _reveal(int index, Widget child) {
    final start = (0.2 + index * 0.1).clamp(0.0, 0.8);
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        start,
        (start + 0.3).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final fashion = report.fashion;
    final palette = AppPalette.of(context);
    final sections = <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'カルチャー情報',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Hint('調べたアーティスト: ${report.artist}'),
        ],
      ),
      if (fashion.styles.isNotEmpty || fashion.colors.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CultureChips(label: 'スタイル', values: fashion.styles),
            CultureColors(values: fashion.colors),
          ],
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CultureLabel('この MV の衣装'),
          const SizedBox(height: 2),
          _OutfitDigest(outfit: report.mvOutfit),
        ],
      ),
      GroundingFooter(
        sources: report.sources,
        searchSuggestionsHtml: report.searchSuggestionsHtml,
        webSearchQueries: report.webSearchQueries,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => showCultureDetailSheet(context, report),
          icon: const Icon(Icons.unfold_more),
          label: const Text('くわしく見る'),
        ),
      ),
    ];

    return ScaleTransition(
      scale: Tween(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0, 0.7, curve: Curves.elasticOut),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // 背景は MV の色に合わせる(文字は濃い色のまま読めるよう、薄い色 → 白)
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.selected, Colors.white],
          ),
          border: Border.all(color: palette.accent.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, section) in sections.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              _reveal(i, section),
            ],
          ],
        ),
      ),
    );
  }
}

/// この MV の衣装の要約(シーンごとに 1 行。最大 2 件 +「ほか n 件」)。
class _OutfitDigest extends StatelessWidget {
  const _OutfitDigest({required this.outfit});

  final MvOutfit outfit;

  static const _max = 2;

  @override
  Widget build(BuildContext context) {
    final problem = mvOutfitProblem(outfit);
    if (problem != null) return Text(problem);
    final looks = outfit.looks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final look in looks.take(_max))
          Text(
            [
              if (look.label.isNotEmpty) '${look.label}: ',
              look.items.map(describeOutfitItem).join('、'),
            ].join(),
          ),
        if (looks.length > _max) Hint('ほか ${looks.length - _max} 件'),
      ],
    );
  }
}

/// カルチャー情報を調べている間、① ② の検索の下に出す「入力を止めている理由」(spec 038 AC-19)。
class CultureLockHint extends StatelessWidget {
  const CultureLockHint({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.lock_clock, size: 16, color: AppColors.muted),
          SizedBox(width: 6),
          Expanded(child: Hint('カルチャー情報を調べ終わるまで、検索・選び直しはできません')),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        CircularProgressIndicator(),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('カルチャー情報を調べています', style: _bold),
              Hint('Google 検索と MV の映像の解析をしているため、数十秒かかることがあります'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('カルチャー情報を取得できませんでした', style: _bold),
        const SizedBox(height: 4),
        ErrorText(message),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('再試行'),
        ),
      ],
    );
  }
}

class _Unidentified extends StatelessWidget {
  const _Unidentified({required this.report});

  final CultureReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('アーティストを特定できませんでした', style: _bold),
        const SizedBox(height: 4),
        Text(report.message),
        // 検索は実行されているため、出典と検索候補は表示する
        GroundingFooter(
          sources: report.sources,
          searchSuggestionsHtml: report.searchSuggestionsHtml,
          webSearchQueries: report.webSearchQueries,
        ),
      ],
    );
  }
}

const _bold = TextStyle(fontWeight: FontWeight.bold);
