import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/core/widgets.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_detail_sheet.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_section.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_section.dart';
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

    // 他の候補は畳まれ、取得中は「変更」を押しても反応しない(spec 038 AC-6)
    expect(find.text('アイドル LIVE映像'), findsNothing);
    await tester.tap(find.text('変更'));
    await tester.pump();
    expect(find.text('アイドル LIVE映像'), findsNothing);
    expect(find.text('カルチャー情報を調べています'), findsOneWidget);
    expect(repo.queries, hasLength(2));
    expect(culture.videos, hasLength(1));

    pending.complete(fullReport);
    await tester.pumpAndSettle();

    // 取得が終われば「変更」で一覧に戻して別の候補を選べ、取得し直す(009 AC-2 / 038 AC-5)
    await tester.tap(find.text('変更'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('アイドル LIVE映像'));
    await tester.pumpAndSettle();

    expect(culture.videos.map((v) => v.videoId), [
      'abcDEF12345',
      'zyxWVU98765',
    ]);
    expect(find.text('アイドル LIVE映像'), findsOneWidget);
    expect(find.text('YOASOBI「アイドル」 Official Music Video'), findsNothing);
  });

  testWidgets('取得中は ① ② の検索の下に理由を出し、終わると消える(spec 038 AC-19)', (tester) async {
    const reason = 'カルチャー情報を調べ終わるまで、検索・選び直しはできません';
    final pending = Completer<CultureReport>();
    final culture = FakeCultureRepository((video) => pending.future);
    await _pumpScreen(tester, _mvRepository(), culture);

    expect(find.text(reason), findsNothing);

    await _submit(tester, 'https://youtu.be/abcDEF12345');

    expect(find.text(reason), findsNWidgets(2));
    // ① の検索ボタンの下と、② の検索ボタンの下
    final mvButton = tester.getBottomLeft(find.byKey(mvSearchButtonKey)).dy;
    final liveButton = tester.getBottomLeft(find.byKey(liveSearchButtonKey)).dy;
    final reasons = tester.getTopLeft(find.text(reason).first).dy;
    final reasons2 = tester.getTopLeft(find.text(reason).last).dy;
    expect(reasons > mvButton && reasons < liveButton, isTrue);
    expect(reasons2 > liveButton, isTrue);

    pending.complete(fullReport);
    await tester.pumpAndSettle();

    expect(find.text(reason), findsNothing);
  });

  testWidgets('取得が終わると要点のカードを出し、出典と検索候補も表示する(AC-3, AC-5 / 038 AC-7)', (
    tester,
  ) async {
    final culture = FakeCultureRepository((video) async => fullReport);
    await _pumpScreen(tester, _mvRepository(), culture);

    await _submit(tester, 'https://youtu.be/abcDEF12345');
    await tester.pumpAndSettle();

    final card = find.byType(CultureSummaryCard);
    Finder inCard(Finder f) => find.descendant(of: card, matching: f);
    expect(inCard(find.text('調べたアーティスト: YOASOBI')), findsOneWidget);
    expect(inCard(find.widgetWithText(Pill, 'ストリート')), findsOneWidget);
    // よく使う色は色の丸付き
    expect(inCard(find.text('黒')), findsOneWidget);
    expect(inCard(find.byKey(const ValueKey('color-dot-黒'))), findsOneWidget);
    expect(inCard(find.text('この MV の衣装')), findsOneWidget);
    expect(
      inCard(find.text('メインの衣装: ワンピース(白 / ガーリー / ミニ丈) フリル')),
      findsOneWidget,
    );
    // 出典はタップで開けるリンク(spec 015)
    expect(inCard(find.text('参照した情報源:')), findsOneWidget);
    expect(inCard(find.text('[1] 記事A')), findsOneWidget);
    // Web 以外(テスト)では検索候補の代わりに検索クエリを出す
    expect(inCard(find.widgetWithText(Chip, 'YOASOBI ファッション')), findsOneWidget);
    expect(inCard(find.text('くわしく見る')), findsOneWidget);
    // 経歴などはポップアップを開くまで出さない
    expect(find.text('・2019年 結成'), findsNothing);
    expect(find.text('アニメーションと実写の融合'), findsNothing);
  });

  testWidgets('「くわしく見る」でポップアップが開き、3 つのタブで全項目を見られる(AC-4 / 038 AC-8〜10)', (
    tester,
  ) async {
    final culture = FakeCultureRepository((video) async => fullReport);
    await _pumpScreen(tester, _mvRepository(), culture);
    await _submit(tester, 'https://youtu.be/abcDEF12345');
    await tester.pumpAndSettle();

    await tester.tap(find.text('くわしく見る'));
    await tester.pumpAndSettle();

    final sheet = find.byType(CultureDetailSheet);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
    void footerShown() {
      expect(inSheet(find.text('[1] 記事A')), findsOneWidget);
      expect(inSheet(find.text('[2] 記事B')), findsOneWidget);
      expect(inSheet(find.text('[3] example.net')), findsOneWidget);
      expect(
        inSheet(find.widgetWithText(Chip, 'YOASOBI ファッション')),
        findsOneWidget,
      );
    }

    // 初期はファッションのタブ
    expect(sheet, findsOneWidget);
    expect(
      tester.widget<TabBar>(inSheet(find.byType(TabBar))).controller ??
          DefaultTabController.of(tester.element(inSheet(find.byType(TabBar)))),
      isA<TabController>().having((c) => c.index, 'index', 0),
    );
    for (final chip in ['ストリート', 'ベレー帽']) {
      expect(inSheet(find.widgetWithText(Pill, chip)), findsOneWidget);
    }
    expect(inSheet(find.text('白')), findsOneWidget);
    expect(inSheet(find.text('アニメーションと実写の融合')), findsOneWidget);
    expect(inSheet(find.text('出典: [1] [2]')), findsOneWidget);
    footerShown();

    await tester.tap(inSheet(find.text('MV の衣装')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('メインの衣装')), findsOneWidget);
    expect(inSheet(find.text('・ワンピース(白 / ガーリー / ミニ丈) フリル')), findsOneWidget);
    expect(inSheet(find.text('根拠: MV の映像')), findsOneWidget);
    footerShown();

    await tester.tap(inSheet(find.text('経歴・音楽性')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('小説を音楽にするユニット')), findsOneWidget);
    expect(inSheet(find.text('・2019年 結成')), findsOneWidget);
    expect(inSheet(find.widgetWithText(Pill, 'J-POP')), findsOneWidget);
    expect(inSheet(find.text('・夜に駆ける')), findsOneWidget);
    expect(inSheet(find.text('出典: [1]')), findsOneWidget);
    footerShown();
  });

  group('ポップアップは ✕ / 背景 / Esc / 下へのスワイプで閉じる(038 AC-11)', () {
    Future<void> open(WidgetTester tester) async {
      final culture = FakeCultureRepository((video) async => fullReport);
      await _pumpScreen(tester, _mvRepository(), culture);
      await _submit(tester, 'https://youtu.be/abcDEF12345');
      await tester.pumpAndSettle();
      await tester.tap(find.text('くわしく見る'));
      await tester.pumpAndSettle();
      expect(find.byType(CultureDetailSheet), findsOneWidget);
    }

    testWidgets('✕', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(cultureSheetCloseKey));
      await tester.pumpAndSettle();
      expect(find.byType(CultureDetailSheet), findsNothing);
      expect(find.byType(CultureSummaryCard), findsOneWidget);
    });

    testWidgets('背景', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(600, 20));
      await tester.pumpAndSettle();
      expect(find.byType(CultureDetailSheet), findsNothing);
    });

    testWidgets('Esc', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CultureDetailSheet), findsNothing);
    });

    testWidgets('下へのスワイプ', (tester) async {
      await open(tester);
      await tester.fling(find.text('カルチャー情報').last, const Offset(0, 800), 2000);
      await tester.pumpAndSettle();
      expect(find.byType(CultureDetailSheet), findsNothing);
    });
  });

  testWidgets('動きを減らす設定では、要点のカードは最初から表示済み(038 AC-17)', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: panelApp(
          MvLookupPanel(
            repository: _mvRepository(),
            cultureRepository: FakeCultureRepository(
              (video) async => fullReport,
            ),
            liveRepository: FakeLiveRepository(),
          ),
        ),
      ),
    );
    await _submit(tester, 'https://youtu.be/abcDEF12345');
    await tester.pump();

    // 時間を進めなくても、項目が見えている(拡大・フェードの途中ではない)
    final fades = tester.widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(CultureSummaryCard),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades, isNotEmpty);
    expect(fades.every((f) => f.opacity.value == 1), isTrue);
    final scale = tester.widget<ScaleTransition>(
      find
          .descendant(
            of: find.byType(CultureSummaryCard),
            matching: find.byType(ScaleTransition),
          )
          .first,
    );
    expect(scale.scale.value, 1);
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

    // よく使う色は色の丸付きで出る(spec 038)
    expect(find.byKey(const ValueKey('color-dot-黒')), findsOneWidget);
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
