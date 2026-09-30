import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_section.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_screen.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';

import 'mv_lookup_fakes.dart';

const _video = MvVideo(
  videoId: 'abcDEF12345',
  url: 'https://www.youtube.com/watch?v=abcDEF12345',
  artist: 'YOASOBI',
  songTitle: 'アイドル',
  titleParsed: true,
  title: 'YOASOBI「アイドル」 Official Music Video',
  channelTitle: 'YOASOBI',
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeLiveRepository live,
  FakeCultureRepository? culture,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MvLookupScreen(
        repository: FakeMvRepository(
          (query) async =>
              const MvLookupResult(inputType: 'url', video: _video),
        ),
        cultureRepository: culture ?? FakeCultureRepository(),
        liveRepository: live,
      ),
    ),
  );
}

Future<void> _submitMv(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(mvQueryFieldKey), query);
  await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
  await tester.pump();
  await tester.pump();
}

Future<void> _searchLive(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(liveQueryFieldKey), query);
  await tester.tap(find.widgetWithIcon(IconButton, Icons.travel_explore));
  await tester.pump();
  await tester.pump();
}

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<TextField>(find.byKey(key)).enabled ?? true;

VoidCallback? _button(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon)).onPressed;

/// その候補カードの中に選択済みのアイコンがあるか。
bool _isSelected(WidgetTester tester, String liveName) => tester.any(
  find.descendant(
    of: find
        .ancestor(of: find.text(liveName), matching: find.byType(Card))
        .first,
    matching: find.byIcon(Icons.check_circle),
  ),
);

void main() {
  testWidgets('ライブ情報も日付も空なら入力エラーを出し、API は呼ばない(AC-6)', (tester) async {
    final live = FakeLiveRepository();
    await _pumpScreen(tester, live: live);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.travel_explore));
    await tester.pump();

    expect(find.text('ライブ情報か日付を入力してください'), findsOneWidget);
    expect(live.requests, isEmpty);
  });

  testWidgets(
    '検索すると最大 3 件がライブ名・場所・日付・天気つきで表示される(AC-5, AC-8, AC-9, AC-10, AC-11)',
    (tester) async {
      final live = FakeLiveRepository();
      await _pumpScreen(tester, live: live);

      expect(find.text('アーティストは入力から特定します'), findsOneWidget);

      await _searchLive(tester, '電光石火');
      await tester.pumpAndSettle();

      // 動画を表示していないので、アーティストは条件に付けず候補ごとに出す
      expect(live.requests.single.query, '電光石火');
      expect(live.requests.single.artist, isNull);
      expect(find.text('アーティスト: YOASOBI'), findsNWidgets(3));
      expect(find.text('公演A'), findsOneWidget);
      expect(find.text('場所: さいたまスーパーアリーナ(埼玉県さいたま市)'), findsOneWidget);
      expect(find.text('日付: 2023/06/04'), findsOneWidget);
      // 天気は実績 / 予報 / 予報はまだ無い、を区別して出す
      expect(find.text('天気: 晴れ / 最高 27℃ / 最低 18℃(実績)'), findsOneWidget);
      expect(find.text('天気: 雨 / 降水確率 80%(予報)'), findsOneWidget);
      expect(find.text('天気: 予報はまだありません'), findsOneWidget);
      // 出典と検索候補
      expect(find.text('出典: [1]'), findsOneWidget);
      expect(find.text('[1] ライブ記事'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'YOASOBI ライブ 2023'), findsOneWidget);
    },
  );

  testWidgets('表示中の動画のアーティストを条件に使い、候補にはアーティスト名を出さない(AC-7)', (tester) async {
    final live = FakeLiveRepository();
    await _pumpScreen(
      tester,
      live: live,
      culture: FakeCultureRepository((video) async => fullReport),
    );

    await _submitMv(tester, 'https://youtu.be/abcDEF12345');
    await tester.pumpAndSettle();
    expect(find.text('アーティスト: YOASOBI(表示中の動画から)'), findsOneWidget);

    await _searchLive(tester, '電光石火');
    await tester.pumpAndSettle();

    expect(live.requests.single.artist, 'YOASOBI');
    expect(find.text('公演A'), findsOneWidget);
    expect(find.text('アーティスト: YOASOBI'), findsNothing);
  });

  testWidgets('日付だけでも検索できる(AC-5)', (tester) async {
    final live = FakeLiveRepository();
    await _pumpScreen(tester, live: live);

    await tester.tap(find.widgetWithText(OutlinedButton, '日付'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await _searchLive(tester, '');
    await tester.pumpAndSettle();

    final request = live.requests.single;
    expect(request.query, '');
    expect(request.date, DateUtils.dateOnly(DateTime.now()));
  });

  testWidgets('候補を 1 件選ぶと強調表示され、別の候補を選ぶと選択が移る(AC-12)', (tester) async {
    await _pumpScreen(tester, live: FakeLiveRepository());
    await _searchLive(tester, '電光石火');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle), findsNothing);

    await tester.tap(find.text('公演B'));
    await tester.pump();
    expect(_isSelected(tester, '公演B'), isTrue);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.text('公演C'));
    await tester.pump();
    expect(_isSelected(tester, '公演C'), isTrue);
    expect(_isSelected(tester, '公演B'), isFalse);
  });

  testWidgets('見つからなければその旨を出す(AC-13)', (tester) async {
    final live = FakeLiveRepository(
      (request) async =>
          const LiveSearchResult(found: false, message: '条件に合う公演がありません。'),
    );
    await _pumpScreen(tester, live: live);

    await _searchLive(tester, '存在しないライブ');
    await tester.pumpAndSettle();

    expect(find.text('該当するライブが見つかりませんでした'), findsOneWidget);
    expect(find.text('条件に合う公演がありません。'), findsOneWidget);
  });

  testWidgets('失敗したらエラーと再試行を出し、同じ条件で呼び直す(AC-15)', (tester) async {
    var attempts = 0;
    final live = FakeLiveRepository((request) async {
      attempts++;
      if (attempts == 1) {
        throw ApiException(
          '{"detail":"Gemini のクォータ(利用上限)を超えました。"}',
          statusCode: 503,
        );
      }
      return liveResult(artistKnown: false);
    });
    await _pumpScreen(tester, live: live);

    await _searchLive(tester, '電光石火');
    await tester.pumpAndSettle();

    expect(find.text('Gemini のクォータ(利用上限)を超えました。'), findsOneWidget);

    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();

    expect(live.requests.map((r) => r.query), ['電光石火', '電光石火']);
    expect(find.text('公演A'), findsOneWidget);
  });

  testWidgets('ライブの検索中は MV 検索ページの他の入力を受け付けない(AC-14)', (tester) async {
    final pending = Completer<LiveSearchResult>();
    await _pumpScreen(
      tester,
      live: FakeLiveRepository((request) => pending.future),
    );

    await _searchLive(tester, '電光石火');

    expect(find.text('ライブ情報を調べています'), findsOneWidget);
    expect(_enabled(tester, mvQueryFieldKey), isFalse);
    expect(_enabled(tester, liveQueryFieldKey), isFalse);
    expect(_button(tester, Icons.search), isNull);
    expect(_button(tester, Icons.travel_explore), isNull);

    pending.complete(liveResult());
    await tester.pumpAndSettle();

    expect(_enabled(tester, mvQueryFieldKey), isTrue);
    expect(_button(tester, Icons.travel_explore), isNotNull);
  });

  testWidgets('カルチャー情報の取得中はライブの検索を受け付けない(AC-14)', (tester) async {
    final pending = Completer<CultureReport>();
    await _pumpScreen(
      tester,
      live: FakeLiveRepository(),
      culture: FakeCultureRepository((video) => pending.future),
    );

    await _submitMv(tester, 'https://youtu.be/abcDEF12345');

    expect(find.text('カルチャー情報を調べています'), findsOneWidget);
    expect(_enabled(tester, liveQueryFieldKey), isFalse);
    expect(_button(tester, Icons.travel_explore), isNull);

    pending.complete(fullReport);
    await tester.pumpAndSettle();

    expect(_button(tester, Icons.travel_explore), isNotNull);
  });
}
