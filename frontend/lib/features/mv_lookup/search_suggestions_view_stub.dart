import 'package:flutter/material.dart';

import 'search_query_chips.dart';

/// Google 検索の検索候補の代わりに、実行された検索クエリを文字で表示する(Web 以外用)。
///
/// Web 以外では API が返す HTML を描画できないため。モバイル向けに公開する場合は、
/// WebView などで HTML をそのまま表示する対応が必要(spec 008 の未決事項 1)。
class SearchSuggestionsView extends StatelessWidget {
  const SearchSuggestionsView({
    super.key,
    required this.html,
    required this.queries,
  });

  final String html;
  final List<String> queries;

  @override
  Widget build(BuildContext context) => SearchQueryChips(queries: queries);
}
