import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_section.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_screen.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_snapshot.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';

import 'mv_lookup_fakes.dart';
import 'outfit_fakes.dart';

void main() {
  testWidgets('動画・カルチャー情報・ライブの選択が要約として外へ出る(spec 011 AC-7)', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final snapshots = <MvLookupSnapshot>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MvLookupScreen(
          repository: FakeMvRepository(
            (query) async =>
                const MvLookupResult(inputType: 'url', video: confirmVideo),
          ),
          cultureRepository: FakeCultureRepository((video) async => fullReport),
          liveRepository: FakeLiveRepository(),
          onChanged: snapshots.add,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(mvQueryFieldKey),
      'https://youtu.be/abcDEF12345',
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
    await tester.pumpAndSettle();

    expect(snapshots.any((s) => s.cultureLoading), isTrue);
    var last = snapshots.last;
    expect(last.mvQuery, 'https://youtu.be/abcDEF12345');
    expect(last.video?.videoId, 'abcDEF12345');
    expect(last.culture?.artist, 'YOASOBI');
    expect(last.cultureLoading, isFalse);
    expect(last.artist, 'YOASOBI');
    expect(last.selectedLive, isNull);

    await tester.enterText(find.byKey(liveQueryFieldKey), '電光石火');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.travel_explore));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公演B'));
    await tester.pump();

    last = snapshots.last;
    expect(last.liveQuery, '電光石火');
    expect(last.liveResult?.candidates, hasLength(3));
    expect(last.selectedLive?.liveName, '公演B');
  });
}
