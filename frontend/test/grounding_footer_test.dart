import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/link.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/grounding_footer.dart';

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(
  const MaterialApp(
    home: Scaffold(
      body: GroundingFooter(
        sources: [
          CultureSource(
            index: 1,
            title: 'excite.co.jp',
            url: 'https://example.com/1',
          ),
          CultureSource(index: 2, title: '', url: 'https://example.com/2'),
        ],
        searchSuggestionsHtml: '',
        webSearchQueries: ['YOASOBI ライブ'],
      ),
    ),
  ),
);

void main() {
  late List<Uri> opened;
  late bool result;
  setUp(() {
    opened = [];
    result = true;
    openUrl = (url) async {
      opened.add(url);
      return result;
    };
  });

  testWidgets('出典はタップで開けるリンクになり、検索クエリも出す(spec 015 AC-18)', (tester) async {
    await _pump(tester);

    expect(find.text('参照した情報源:'), findsOneWidget);
    expect(find.text('[2] https://example.com/2'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'YOASOBI ライブ'), findsOneWidget);

    await tester.tap(find.text('[1] excite.co.jp'));
    await tester.pump();

    expect(opened, [Uri.parse('https://example.com/1')]);
    expect(find.text('リンクを開けませんでした'), findsNothing);
  });

  testWidgets('開けなかったときは知らせる', (tester) async {
    result = false;
    await _pump(tester);

    await tester.tap(find.text('[1] excite.co.jp'));
    await tester.pump();

    expect(find.text('リンクを開けませんでした'), findsOneWidget);
  });
}
