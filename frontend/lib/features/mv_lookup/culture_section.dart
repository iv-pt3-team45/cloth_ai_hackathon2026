import 'package:flutter/material.dart';

import 'culture_models.dart';
import 'search_suggestions_view.dart';

/// 動画のアーティストのカルチャー情報(spec 008)を表示する。
///
/// 取得の開始と入力のロックは MV 検索画面が行い、ここは状態に応じた表示だけを担う。
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
      child = _Report(report: report);
    }
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('カルチャー情報を調べています', style: textTheme.titleMedium),
              Text(
                'Google 検索と MV の映像の解析をしているため、数十秒かかることがあります',
                style: textTheme.bodySmall,
              ),
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('カルチャー情報を取得できませんでした', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(message, style: TextStyle(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
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
        Text(
          'アーティストを特定できませんでした',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(report.message),
        // 検索は実行されているため、出典と検索候補は表示する
        ..._groundingFooter(report),
      ],
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.report});

  final CultureReport report;

  @override
  Widget build(BuildContext context) {
    final fashion = report.fashion;
    final background = report.background;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('カルチャー情報', style: Theme.of(context).textTheme.titleLarge),
        Text('調べたアーティスト: ${report.artist}'),
        _Heading('ファッション・ビジュアル'),
        if (fashion.isEmpty) const Text('情報が見つかりませんでした'),
        _Chips(label: 'スタイル', values: fashion.styles),
        _Chips(label: 'よく使う色', values: fashion.colors),
        _Chips(label: '定番のアイテム', values: fashion.items),
        _Paragraph(label: '世界観', text: fashion.worldview),
        _Citations(indices: fashion.sourceIndices),
        _Heading('この MV の衣装'),
        _Outfit(outfit: report.mvOutfit),
        _Heading('経歴・音楽性'),
        if (background.isEmpty) const Text('情報が見つかりませんでした'),
        _Paragraph(label: '概要', text: background.summary),
        _Bullets(label: '活動の歩み', values: background.history),
        _Chips(label: 'ジャンル', values: background.genres),
        _Bullets(label: '代表曲', values: background.representativeSongs),
        _Paragraph(label: '音楽的な特徴', text: background.musicalTraits),
        _Citations(indices: background.sourceIndices),
        ..._groundingFooter(report),
      ],
    );
  }
}

/// 出典の一覧と検索候補。Grounding with Google Search の利用条件により表示する。
List<Widget> _groundingFooter(CultureReport report) => [
  if (report.sources.isNotEmpty) ...[
    _Heading('出典'),
    for (final source in report.sources) _SourceTile(source: source),
  ],
  if (report.searchSuggestionsHtml.isNotEmpty ||
      report.webSearchQueries.isNotEmpty) ...[
    const SizedBox(height: 12),
    SearchSuggestionsView(
      html: report.searchSuggestionsHtml,
      queries: report.webSearchQueries,
    ),
  ],
];

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.labelLarge);
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(label),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [for (final v in values) Chip(label: Text(v))],
          ),
        ],
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_Label(label), SelectableText(text)],
      ),
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_Label(label), for (final v in values) Text('・$v')],
      ),
    );
  }
}

/// セクションの根拠になった出典番号(項目の近くに示す)。
class _Citations extends StatelessWidget {
  const _Citations({required this.indices});

  final List<int> indices;

  @override
  Widget build(BuildContext context) {
    if (indices.isEmpty) return const SizedBox.shrink();
    return Text(
      '出典: ${indices.map((i) => '[$i]').join(' ')}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _Outfit extends StatelessWidget {
  const _Outfit({required this.outfit});

  final MvOutfit outfit;

  @override
  Widget build(BuildContext context) {
    if (!outfit.isOk) {
      return Text(
        outfit.message.isEmpty ? 'MV の映像を解析できませんでした' : outfit.message,
      );
    }
    if (outfit.looks.isEmpty) return const Text('映像から衣装を読み取れませんでした');

    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final look in outfit.looks) ...[
          if (look.label.isNotEmpty)
            Text(look.label, style: textTheme.titleSmall),
          for (final item in look.items) Text('・${_describe(item)}'),
          const SizedBox(height: 4),
        ],
        Text('根拠: MV の映像', style: textTheme.bodySmall),
      ],
    );
  }

  /// 例: 「ワンピース(白・ピンク / ガーリー / ミニ丈)フリル」
  static String _describe(OutfitItem item) {
    final details = [
      if (item.colors.isNotEmpty) item.colors.join('・'),
      if (item.style.isNotEmpty) item.style,
      if (item.shape.isNotEmpty) item.shape,
    ];
    final head = details.isEmpty
        ? item.category
        : '${item.category}(${details.join(' / ')})';
    return item.notes.isEmpty ? head : '$head ${item.notes}';
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final CultureSource source;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Vertex AI はタイトルにドメイン名を入れて返すことがあるため、同じなら重ねて出さない
    final domain = source.domain.isEmpty || source.domain == source.title
        ? ''
        : '(${source.domain})';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('[${source.index}] ${source.title}$domain'),
          SelectableText(source.url, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}
