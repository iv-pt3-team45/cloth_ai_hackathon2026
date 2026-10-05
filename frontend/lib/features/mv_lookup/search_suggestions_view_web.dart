import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

import 'search_query_chips.dart';

/// Google 検索の検索候補(Search Suggestions)を表示する(Web 用)。
///
/// Grounding with Google Search の利用条件により表示が必須のため、
/// API が返した HTML を加工せずに `<div>` の中へ入れる。
/// HTML が返らなかったときは、空の枠を出さずに検索クエリを出す(spec 015)。
class SearchSuggestionsView extends StatelessWidget {
  const SearchSuggestionsView({
    super.key,
    required this.html,
    required this.queries,
  });

  final String html;
  final List<String> queries;

  @override
  Widget build(BuildContext context) {
    if (html.isEmpty) return SearchQueryChips(queries: queries);
    return SizedBox(
      height: 80,
      child: HtmlElementView.fromTagName(
        // 要素は作成時にしか中身を入れないため、HTML が変わったら作り直す
        key: ValueKey(html),
        tagName: 'div',
        onElementCreated: (Object element) {
          final div = element as JSObject;
          div['innerHTML'] = html.toJS;
          (div['style'] as JSObject)['overflow'] = 'auto'.toJS;
        },
      ),
    );
  }
}
