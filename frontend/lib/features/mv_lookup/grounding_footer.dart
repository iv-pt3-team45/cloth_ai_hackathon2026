import 'package:flutter/material.dart';

import 'culture_models.dart';
import 'search_suggestions_view.dart';

/// Google 検索の出典の一覧と検索候補(spec 008 / 009)。
///
/// Grounding with Google Search の利用条件により、検索した結果には必ず添えて表示する。
class GroundingFooter extends StatelessWidget {
  const GroundingFooter({
    super.key,
    required this.sources,
    required this.searchSuggestionsHtml,
    required this.webSearchQueries,
  });

  final List<CultureSource> sources;
  final String searchSuggestionsHtml;
  final List<String> webSearchQueries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sources.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text('出典', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final source in sources) _SourceTile(source: source),
        ],
        if (searchSuggestionsHtml.isNotEmpty ||
            webSearchQueries.isNotEmpty) ...[
          const SizedBox(height: 12),
          SearchSuggestionsView(
            html: searchSuggestionsHtml,
            queries: webSearchQueries,
          ),
        ],
      ],
    );
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
