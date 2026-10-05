import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/core/widgets.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_panel.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';

import 'mv_lookup_fakes.dart';

MvVideo _video(String id) => MvVideo(
  videoId: id,
  url: 'https://www.youtube.com/watch?v=$id',
  artist: 'YOASOBI',
  songTitle: 'アイドル',
  titleParsed: true,
  title: 'YOASOBI「アイドル」 Official Music Video',
  channelTitle: 'YOASOBI',
);

const _candidates = [
  MvCandidate(
    videoId: 'abcDEF12345',
    url: 'https://www.youtube.com/watch?v=abcDEF12345',
    title: 'YOASOBI「アイドル」 Official Music Video',
    channelTitle: 'YOASOBI',
  ),
  MvCandidate(
    videoId: 'zyxWVU98765',
    url: 'https://www.youtube.com/watch?v=zyxWVU98765',
    title: 'アイドル LIVE映像',
    channelTitle: 'YOASOBI',
  ),
];

/// URL なら動画、それ以外なら候補を返す(URL の末尾 11 文字を動画 ID とみなす)。
FakeMvRepository _mvRepository() => FakeMvRepository(
  (query) async => query.startsWith('https://')
      ? MvLookupResult(
          inputType: 'url',
          video: _video(query.substring(query.length - 11)),
        )
      : const MvLookupResult(inputType: 'keyword', candidates: _candidates),
);

Future<void> _pumpScreen(
  WidgetTester tester,
  FakeMvRepository repo,
  FakeCultureRepository culture,
) async {
  // 動画情報の下にあるカルチャー情報まで一度に描画されるよう、画面を縦に長くする
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    panelApp(
      MvLookupPanel(
        repository: repo,
        cultureRepository: culture,
        liveRepository: FakeLiveRepository(),
      ),
    ),
  );
}

/// 入力して実行する。カルチャー情報の取得中はローディングが回り続けるため
/// pumpAndSettle は使わない。
Future<void> _submit(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(mvQueryFieldKey), query);
  await tester.tap(find.byKey(mvSearchButtonKey));
  await tester.pump();
  await tester.pump();
}

bool _inputEnabled(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(mvQueryFieldKey)).enabled ?? true;

VoidCallback? _searchButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(mvSearchButtonKey)).onPressed;

void main() {
  testWidgets('URL で動画が表示されると自動で取得が始まり、取得中は入力を受け付けない(AC-1, AC-2)', (
    tester,
  ) async {
    final pending = Completer<CultureReport>();
    final culture = FakeCultureRepository((video) => pending.future);
    await _pumpScreen(tester, _mvRepository(), culture);

    await _submit(tester, 'https://youtu.be/abcDEF12345');

    expect(culture.videos.single.videoId, 'abcDEF12345');
    expect(find.text('カルチャー情報を調べています'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_inputEnabled(tester), isFalse);
    expect(_searchButton(tester), isNull);

    pending.complete(fullReport);
    await tester.pumpAndSettle();

    expect(find.text('カルチャー情報'), findsOneWidget);
    expect(_inputEnabled(tester), isTrue);
    expect(_searchButton(tester), isNotNull);
  });

  testWidgets('候補を選ぶと自動で取得が始まり、取得中は他の候補を押せない(008 AC-1, AC-2 / 009 AC-4)', (
    tester,
  ) async {
    final pending = Completer<CultureReport>();
    final culture = FakeCultureRepository(
      (video) => video.videoId == 'abcDEF12345'
          ? pending.future
          : Future.value(fullReport),
    );
    final repo = _mvRepository();
    await _pumpScreen(tester, repo, culture);

    await _submit(tester, 'アイドル');
    expect(culture.videos, isEmpty); // 候補を眺めるだけでは呼ばない

    await tester.tap(find.text('YOASOBI「アイドル」 Official Music Video'));
    await tester.pump();
    await tester.pump();

    expect(culture.videos.single.videoId, 'abcDEF12345');
    expect(_inputEnabled(tester), isFalse);

    // 取得中は他の候補を押しても反応しない
    await tester.tap(find.text('アイドル LIVE映像'));
    await tester.pump();
    expect(repo.queries, hasLength(2));
    expect(culture.videos, hasLength(1));

    pending.complete(fullReport);
    await tester.pumpAndSettle();

    // 取得が終われば別の候補を選べ、前の展開は閉じて取得し直す(009 AC-2)
    await tester.tap(find.text('アイドル LIVE映像'));
    await tester.pumpAndSettle();

    expect(culture.videos.map((v) => v.videoId), [
      'abcDEF12345',
      'zyxWVU98765',
    ]);
    // 展開していない候補(1 件目)だけが右向きの矢印になる
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(
      find.text('https://www.youtube.com/watch?v=zyxWVU98765'),
      findsOneWidget,
    );
    expect(
      find.text('https://www.youtube.com/watch?v=abcDEF12345'),
      findsNothing,
    );
  });

  testWidgets('取得が終わると項目ごとに整理して、出典と検索候補も表示する(AC-3, AC-4, AC-5)', (
    tester,
  ) async {
    final culture = FakeCultureRepository((video) async => fullReport);
    await _pumpScreen(tester, _mvRepository(), culture);

    await _submit(tester, 'https://youtu.be/abcDEF12345');
    await tester.pumpAndSettle();

    expect(find.text('調べたアーティスト: YOASOBI'), findsOneWidget);
    expect(find.text('ファッション・ビジュアル'), findsOneWidget);
    for (final chip in ['ストリート', '黒', '白', 'ベレー帽', 'J-POP']) {
      expect(find.widgetWithText(Pill, chip), findsOneWidget);
    }
    expect(find.text('アニメーションと実写の融合'), findsOneWidget);
    expect(find.text('この MV の衣装'), findsOneWidget);
    expect(find.text('メインの衣装'), findsOneWidget);
    expect(find.text('・ワンピース(白 / ガーリー / ミニ丈) フリル'), findsOneWidget);
    expect(find.text('経歴・音楽性'), findsOneWidget);
    expect(find.text('・2019年 結成'), findsOneWidget);
    expect(find.text('・夜に駆ける'), findsOneWidget);
    // 項目の近くの出典番号と、出典の一覧
    expect(find.text('出典: [1] [2]'), findsOneWidget);
    expect(find.text('出典: [1]'), findsOneWidget);
    // 出典はタップで開けるリンク(spec 015)
    expect(find.text('参照した情報源:'), findsOneWidget);
    expect(find.text('[1] 記事A'), findsOneWidget);
    expect(find.text('[2] 記事B'), findsOneWidget);
    expect(find.text('[3] example.net'), findsOneWidget);
    // Web 以外(テスト)では検索候補の代わりに検索クエリを出す
    expect(find.widgetWithText(Chip, 'YOASOBI ファッション'), findsOneWidget);
  });

  testWidgets('MV の映像を解析できなかった場合はその旨を出す(AC-6)', (tester) async {
    final culture = FakeCultureRepository(
      (video) async => const CultureReport(
        artist: 'YOASOBI',
        identified: true,
        fashion: FashionInfo(colors: ['黒']),
        mvOutfit: MvOutfit(
          status: 'unavailable',
          message: 'MV の映像を解析できませんでした。公開されていない動画や年齢制限のある動画は解析できません。',
        ),
      ),
    );
    await _pumpScreen(tester, _mvRepository(), culture);

    await _submit(tester, 'https://youtu.be/abcDEF12345');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Pill, '黒'), findsOneWidget);
    expect(find.textContaining('映像を解析できませんでした'), findsOneWidget);
  });

  testWidgets('アーティストを特定できなければ推測で埋めない(AC-8)', (tester) async {
    final culture = FakeCultureRepository(
      (video) async => const CultureReport(
        artist: '',
        identified: false,
        message: '音楽の動画ではありませんでした。',
      ),
    );
    await _pumpScreen(tester, _mvRepository(), culture);

    await _submit(tester, 'https://youtu.be/abcDEF12345');
    await tester.pumpAndSettle();

    expect(find.text('アーティストを特定できませんでした'), findsOneWidget);
    expect(find.text('音楽の動画ではありませんでした。'), findsOneWidget);
    expect(find.text('ファッション・ビジュアル'), findsNothing);
  });

  testWidgets('失敗したらエラーと再試行ボタンを出し、再試行で取得し直す(AC-9)', (tester) async {
    var attempts = 0;
    final culture = FakeCultureRepository((video) async {
      attempts++;
      if (attempts == 1) {
        throw ApiException(
          '{"detail":"Gemini のクォータ(利用上限)を超えました。"}',
          statusCode: 503,
        );
      }
      return fullReport;
    });
    await _pumpScreen(tester, _mvRepository(), culture);

    await _submit(tester, 'https://youtu.be/abcDEF12345');
    await tester.pumpAndSettle();

    expect(find.text('Gemini のクォータ(利用上限)を超えました。'), findsOneWidget);
    // 動画情報はそのまま表示されている
    expect(find.text('アイドル'), findsOneWidget);
    expect(_inputEnabled(tester), isTrue);

    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();

    expect(culture.videos, hasLength(2));
    expect(find.text('カルチャー情報'), findsOneWidget);
  });

  testWidgets('別の動画を表示すると前の結果は消え、取得し直す(AC-10)', (tester) async {
    final second = Completer<CultureReport>();
    final culture = FakeCultureRepository(
      (video) => video.videoId == 'abcDEF12345'
          ? Future.value(fullReport)
          : second.future,
    );
    await _pumpScreen(tester, _mvRepository(), culture);

    await _submit(tester, 'https://youtu.be/abcDEF12345');
    await tester.pumpAndSettle();
    expect(find.text('調べたアーティスト: YOASOBI'), findsOneWidget);

    await _submit(tester, 'https://youtu.be/zyxWVU98765');

    expect(find.text('調べたアーティスト: YOASOBI'), findsNothing);
    expect(find.text('カルチャー情報を調べています'), findsOneWidget);
    expect(culture.videos.map((v) => v.videoId), [
      'abcDEF12345',
      'zyxWVU98765',
    ]);

    second.complete(fullReport);
    await tester.pumpAndSettle();
  });
}
