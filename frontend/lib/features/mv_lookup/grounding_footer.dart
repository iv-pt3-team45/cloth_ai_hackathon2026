import 'package:flutter/material.dart';

import '../../core/link.dart';
import '../../core/widgets.dart';
import 'culture_models.dart';
import 'search_suggestions_view.dart';

/// Google 検索の出典の一覧と検索候補(spec 008 / 009)。
///
/// Grounding with Google Search の利用条件により、検索した結果には必ず添えて表示する。
/// 出典はタップで開けるリンクにする(spec 015)。
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
        if (sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Hint('参照した情報源:'),
                for (final source in sources)
                  ExternalLink(label: _label(source), url: source.url),
              ],
            ),
          ),
        if (searchSuggestionsHtml.isNotEmpty ||
            webSearchQueries.isNotEmpty) ...[
          const SizedBox(height: 8),
          SearchSuggestionsView(
            html: searchSuggestionsHtml,
            queries: webSearchQueries,
          ),
        ],
      ],
    );
  }

  /// 例: [1] excite.co.jp(Vertex AI はタイトルにドメイン名を入れて返すことがある)
  static String _label(CultureSource source) {
    final title = source.title.isEmpty ? source.domain : source.title;
    return '[${source.index}] ${title.isEmpty ? source.url : title}';
  }
}
