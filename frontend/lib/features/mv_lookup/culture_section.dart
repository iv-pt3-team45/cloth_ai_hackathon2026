import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'culture_models.dart';
import 'grounding_footer.dart';

/// 動画のアーティストのカルチャー情報(spec 008)を表示する。
///
/// 取得の開始と入力のロックは [MvLookupPanel] が行い、ここは状態に応じた表示だけを担う。
/// 見た目は薄い茶の枠(spec 015)。
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
    return SoftBox(child: child);
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
        Text(
          'カルチャー情報',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Hint('調べたアーティスト: ${report.artist}'),
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
        GroundingFooter(
          sources: report.sources,
          searchSuggestionsHtml: report.searchSuggestionsHtml,
          webSearchQueries: report.webSearchQueries,
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: _bold),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: AppColors.muted, fontSize: 13),
    );
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
        children: [_Label(label), const SizedBox(height: 4), PillWrap(values)],
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
    return Hint('出典: ${indices.map((i) => '[$i]').join(' ')}');
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final look in outfit.looks) ...[
          if (look.label.isNotEmpty)
            Text(
              look.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          for (final item in look.items) Text('・${_describe(item)}'),
          const SizedBox(height: 4),
        ],
        const Hint('根拠: MV の映像'),
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

const _bold = TextStyle(fontWeight: FontWeight.bold);
