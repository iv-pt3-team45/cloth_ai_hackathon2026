import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_section.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_screen.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_snapshot.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/venue_models.dart';

import 'mv_lookup_fakes.dart';

/// ライブを選んだときに会場の形態を調べる(spec 014)。
Future<List<MvLookupSnapshot>> _pumpScreen(
  WidgetTester tester,
  FakeVenueRepository venue,
) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final snapshots = <MvLookupSnapshot>[];
  await tester.pumpWidget(
    MaterialApp(
      home: MvLookupScreen(
        repository: FakeMvRepository(
          (query) async => const MvLookupResult(inputType: 'url'),
        ),
        cultureRepository: FakeCultureRepository(),
        liveRepository: FakeLiveRepository(),
        venueRepository: venue,
        onChanged: snapshots.add,
      ),
    ),
  );
  return snapshots;
}

Future<void> _searchLive(WidgetTester tester) async {
  await tester.enterText(find.byKey(liveQueryFieldKey), '電光石火');
  await tester.tap(find.widgetWithIcon(IconButton, Icons.travel_explore));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ライブを選ぶと会場の形態を調べ、要約に入る', (tester) async {
    final completer = Completer<VenueFormat>();
    final venue = FakeVenueRepository((live) => completer.future);
    final snapshots = await _pumpScreen(tester, venue);
    await _searchLive(tester);

    await tester.tap(find.text('公演A'));
    await tester.pump();

    // 選んだライブの会場名・所在地・ライブ名・公演日を渡す
    final live = venue.lives.single;
    expect(live.venue, 'さいたまスーパーアリーナ');
    expect(live.location, '埼玉県さいたま市');
    expect(live.liveName, '公演A');
    expect(snapshots.last.venueFormatLoading, isTrue);
    expect(snapshots.last.venueFormat, isNull);
    // 調べている間も、他の入力は止めない
    expect(
      tester.widget<TextField>(find.byKey(mvQueryFieldKey)).enabled ?? true,
      isTrue,
    );

    completer.complete(VenueFormat.standing);
    await tester.pumpAndSettle();

    expect(snapshots.last.venueFormatLoading, isFalse);
    expect(snapshots.last.venueFormat, VenueFormat.standing);
  });

  testWidgets('調べている間に選び直したら、前のライブの結果は捨てる', (tester) async {
    final completers = <String, Completer<VenueFormat>>{};
    final venue = FakeVenueRepository(
      (live) => (completers[live.liveName] = Completer()).future,
    );
    final snapshots = await _pumpScreen(tester, venue);
    await _searchLive(tester);

    await tester.tap(find.text('公演A'));
    await tester.pump();
    await tester.tap(find.text('公演B'));
    await tester.pump();

    // 公演A の結果が後から返っても使わない
    completers['公演A']!.complete(VenueFormat.seated);
    await tester.pumpAndSettle();
    expect(snapshots.last.selectedLive?.liveName, '公演B');
    expect(snapshots.last.venueFormatLoading, isTrue);
    expect(snapshots.last.venueFormat, isNull);

    completers['公演B']!.complete(VenueFormat.mixed);
    await tester.pumpAndSettle();
    expect(snapshots.last.venueFormat, VenueFormat.mixed);
  });

  testWidgets('調べるのに失敗したら不明にする(選択はそのまま)', (tester) async {
    final venue = FakeVenueRepository(
      (live) async => throw ApiException('{"detail": "x"}', statusCode: 500),
    );
    final snapshots = await _pumpScreen(tester, venue);
    await _searchLive(tester);

    await tester.tap(find.text('公演A'));
    await tester.pumpAndSettle();

    expect(snapshots.last.selectedLive?.liveName, '公演A');
    expect(snapshots.last.venueFormatLoading, isFalse);
    expect(snapshots.last.venueFormat, VenueFormat.unknown);
  });

  testWidgets('同じライブをもう一度選んでも、調べ直さない', (tester) async {
    final venue = FakeVenueRepository();
    await _pumpScreen(tester, venue);
    await _searchLive(tester);

    await tester.tap(find.text('公演A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公演A'));
    await tester.pumpAndSettle();

    expect(venue.lives, hasLength(1));
  });

  testWidgets('ライブを検索し直すと、会場の形態もリセットする', (tester) async {
    final venue = FakeVenueRepository();
    final snapshots = await _pumpScreen(tester, venue);
    await _searchLive(tester);
    await tester.tap(find.text('公演A'));
    await tester.pumpAndSettle();
    expect(snapshots.last.venueFormat, VenueFormat.standing);

    await _searchLive(tester);

    expect(snapshots.last.selectedLive, isNull);
    expect(snapshots.last.venueFormat, isNull);
    expect(snapshots.last.venueFormatLoading, isFalse);
  });
}
