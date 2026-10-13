import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/app/home_page.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/core/theme.dart';
import 'package:tx_hackathon_gc/core/widgets.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_section.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_vibe.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/vibe_backdrop.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_section.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_panel.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/venue_models.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_models.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_models.dart';
import 'package:tx_hackathon_gc/main.dart';

import 'mv_lookup_fakes.dart';
import 'outfit_fakes.dart';
import 'wardrobe_fakes.dart';

/// 画面に渡すフェイク一式。
class _Fakes {
  _Fakes({
    List<RegisteredCloth> clothes = const [ownedShirt, ownedJeans],
    Future<CultureReport> Function(MvVideo video)? culture,
    FakeOutfitRepository? outfit,
  }) : mv = FakeMvRepository(
         // URL なら動画、MV 名なら候補 1 件(候補を選ぶと URL で問い合わせ直す)
         (query) async => query.startsWith('https://')
             ? const MvLookupResult(inputType: 'url', video: confirmVideo)
             : const MvLookupResult(
                 inputType: 'keyword',
                 candidates: [
                   MvCandidate(
                     videoId: 'abcDEF12345',
                     url: 'https://www.youtube.com/watch?v=abcDEF12345',
                     title: 'YOASOBI「アイドル」 Official Music Video',
                     channelTitle: 'YOASOBI',
                   ),
                 ],
               ),
       ),
       culture = FakeCultureRepository(culture ?? (video) async => fullReport),
       live = FakeLiveRepository(),
       venue = FakeVenueRepository(),
       wardrobe = FakeWardrobeRepository(items: clothes),
       outfit = outfit ?? FakeOutfitRepository();

  final FakeMvRepository mv;
  final FakeCultureRepository culture;
  final FakeLiveRepository live;
  final FakeVenueRepository venue;
  final FakeWardrobeRepository wardrobe;
  final FakeOutfitRepository outfit;
}

/// 画面を出す。
///
/// 演出の背景の動き(spec 039)は止まらないため、既定では端末の「動きを減らす」を有効にして
/// pumpAndSettle が終わるようにする。動きを確かめるテストだけ [reduceMotion] を false にする。
Future<void> _pump(
  WidgetTester tester,
  _Fakes fakes, {
  Size size = const Size(1200, 6000),
  bool reduceMotion = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: HomePage(
        mvRepository: fakes.mv,
        cultureRepository: fakes.culture,
        liveRepository: fakes.live,
        venueRepository: fakes.venue,
        wardrobeRepository: fakes.wardrobe,
        photoPicker: FakePhotoPicker([]),
        outfitRepository: fakes.outfit,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// ① で URL から動画を表示する(カルチャー情報の取得まで待つ)。
Future<void> _selectMv(WidgetTester tester) async {
  await tester.enterText(find.byKey(mvQueryFieldKey), 'https://youtu.be/abc');
  await tester.tap(find.byKey(mvSearchButtonKey));
  await tester.pumpAndSettle();
}

/// ② でライブを検索して「公演A」を選ぶ。
Future<void> _selectLive(WidgetTester tester) async {
  await tester.enterText(find.byKey(liveQueryFieldKey), '電光石火');
  await tester.tap(find.byKey(liveSearchButtonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text('公演A'));
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester) async {
  await tester.tap(find.text('コーディネートを提案してもらう'));
  await tester.pump();
}

/// 進捗の画面はアニメーションが止まらないため、時間を進めて結果の画面まで待つ。
Future<void> _waitResult(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(donePause);
  await tester.pump(const Duration(milliseconds: 400));
}

/// 段階の Pill が今の段階として強調されているか。
bool _phaseSelected(WidgetTester tester, String label) =>
    tester.widget<Pill>(find.widgetWithText(Pill, label)).bold;

void main() {
  testWidgets('タブは無く、ヘッダーと段階と 3 枚のカードと提案ボタンが並ぶ(AC-1, AC-2)', (tester) async {
    await _pump(tester, _Fakes());

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('はじめてのライブ服'), findsOneWidget);
    expect(find.text('1 入力'), findsOneWidget);
    expect(find.text('2 AIが考え中'), findsOneWidget);
    expect(find.text('3 提案'), findsOneWidget);
    expect(_phaseSelected(tester, '1 入力'), isTrue);
    expect(find.text('MV を選ぶ'), findsOneWidget);
    expect(find.text('行くライブを検索'), findsOneWidget);
    expect(find.text('手持ちの服'), findsOneWidget);
    expect(find.text('コーディネートを提案してもらう'), findsOneWidget);
    // チェックリスト(服は読み込んだ点数を出す)
    expect(find.bySemanticsLabel('MV(未入力)'), findsOneWidget);
    expect(find.bySemanticsLabel('ライブの選択(未入力)'), findsOneWidget);
    expect(find.bySemanticsLabel('手持ちの服(2点)(OK)'), findsOneWidget);
  });

  testWidgets('入力が済んだカードの番号の丸は緑の ✓ になる(spec 039 AC-18)', (tester) async {
    await _pump(tester, _Fakes(clothes: const []));

    bool done(int step) => tester
        .widget<StepBadge>(
          find.byWidgetPredicate((w) => w is StepBadge && w.step == step),
        )
        .done;
    expect([done(1), done(2), done(3)], [false, false, false]);
    expect(find.byIcon(Icons.check), findsNothing);

    await _selectMv(tester);
    expect([done(1), done(2), done(3)], [true, false, false]);

    await _selectLive(tester);
    expect([done(1), done(2), done(3)], [true, true, false]);
    expect(find.bySemanticsLabel('1 済み'), findsOneWidget);
    expect(find.bySemanticsLabel('3'), findsOneWidget);
  });

  testWidgets('服が 1 点以上あれば ③ は最初から ✓(spec 039 AC-18)', (tester) async {
    await _pump(tester, _Fakes());

    final badge = tester.widget<StepBadge>(
      find.byWidgetPredicate((w) => w is StepBadge && w.step == 3),
    );
    expect(badge.done, isTrue);
  });

  group('MV のカルチャーに合わせた演出(spec 039 D)', () {
    CultureReport report({
      List<String> styles = const [],
      List<String> colors = const [],
    }) => CultureReport(
      artist: 'YOASOBI',
      identified: true,
      fashion: FashionInfo(styles: styles, colors: colors),
    );

    AppPalette palette(WidgetTester tester) =>
        AppPalette.of(tester.element(find.text('MV を選ぶ')));
    VibeBackdrop backdrop(WidgetTester tester) =>
        tester.widget<VibeBackdrop>(find.byType(VibeBackdrop));

    /// 動きを止めずに、① で URL から動画を出してカルチャー情報が届くまで進める
    Future<void> selectMvAnimated(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(mvQueryFieldKey),
        'https://youtu.be/abc',
      );
      await tester.tap(find.byKey(mvSearchButtonKey));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    testWidgets('ガーリー → 差し色がよく使う色になり、きらめきが流れる。色が 1 回だけ広がる(AC-13)', (
      tester,
    ) async {
      final fakes = _Fakes(
        culture: (video) async => report(styles: ['ガーリー'], colors: ['ピンク']),
      );
      await _pump(tester, fakes, reduceMotion: false);
      expect(palette(tester), AppPalette.standard);
      expect(backdrop(tester).running, isFalse);

      await selectMvAnimated(tester);

      // 切り替わりの演出が 1 回だけ出て、消える
      expect(find.byType(VibeBurst), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(VibeBurst), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(VibeBurst), findsNothing);

      final expected = AppPalette.readableOnWhite(CultureVibe.colorOf('ピンク')!);
      expect(palette(tester).accent, expected);
      expect(palette(tester).dark, isFalse);
      expect(
        Theme.of(tester.element(find.text('MV を選ぶ'))).colorScheme.primary,
        expected,
      );
      expect(backdrop(tester).effect, VibeEffect.sparkle);
      expect(backdrop(tester).running, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ロック → 背景が暗くなり火花が流れる。白いカードの文字の色は変わらない(AC-14)', (tester) async {
      final fakes = _Fakes(
        culture: (video) async => report(styles: ['ロック'], colors: ['赤']),
      );
      await _pump(tester, fakes, reduceMotion: false);
      Color titleColor() => tester
          .renderObject<RenderParagraph>(find.text('MV を選ぶ'))
          .text
          .style!
          .color!;
      final before = titleColor();

      await selectMvAnimated(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(palette(tester).dark, isTrue);
      expect(palette(tester).backgroundTop.computeLuminance(), lessThan(0.1));
      expect(backdrop(tester).effect, VibeEffect.sparks);
      expect(titleColor(), before);
      expect(titleColor(), AppColors.text);
      // ヘッダーのアプリ名(カードの外)は白にして読めるようにする
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('はじめてのライブ服'))
            .text
            .style!
            .color,
        Colors.white,
      );
      // ヘッダーのログインの状態(spec 038)も暗い背景で読める色にする
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('ゲスト'))
            .text
            .style!
            .color,
        palette(tester).onBackgroundMuted,
      );
      expect(palette(tester).onBackgroundMuted, isNot(AppColors.muted));
    });

    testWidgets('どの演出にも当てはまらず色も取れなければ、配色も背景も今のまま(AC-15)', (tester) async {
      final fakes = _Fakes(
        culture: (video) async => report(styles: ['エレガント'], colors: ['玉虫色']),
      );
      await _pump(tester, fakes, reduceMotion: false);

      await selectMvAnimated(tester);
      expect(find.byType(VibeBurst), findsNothing);
      await tester.pumpAndSettle();

      expect(palette(tester), AppPalette.standard);
      expect(backdrop(tester).effect, isNull);
      expect(find.byType(CultureSummaryCard), findsOneWidget);
    });

    testWidgets('① の「変更」で選択を外すと、元の配色に戻り背景が止まる(AC-16)', (tester) async {
      final fakes = _Fakes(
        culture: (video) async => report(styles: ['ナチュラル'], colors: ['緑']),
      );
      await _pump(tester, fakes);
      await tester.enterText(find.byKey(mvQueryFieldKey), 'アイドル');
      await tester.tap(find.byKey(mvSearchButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('YOASOBI「アイドル」 Official Music Video'));
      await tester.pumpAndSettle();
      expect(backdrop(tester).effect, VibeEffect.petals);
      expect(palette(tester), isNot(AppPalette.standard));

      await tester.tap(find.text('変更'));
      await tester.pumpAndSettle();

      expect(palette(tester), AppPalette.standard);
      expect(backdrop(tester).effect, isNull);
      expect(backdrop(tester).running, isFalse);
    });

    testWidgets('動きを減らす設定では、配色だけ変わり、動きと切り替わりの演出は出ない(AC-17)', (tester) async {
      final fakes = _Fakes(
        culture: (video) async => report(styles: ['ガーリー'], colors: ['ピンク']),
      );
      await _pump(tester, fakes);

      await tester.enterText(
        find.byKey(mvQueryFieldKey),
        'https://youtu.be/abc',
      );
      await tester.tap(find.byKey(mvSearchButtonKey));
      await tester.pump();
      await tester.pump();
      expect(find.byType(VibeBurst), findsNothing);
      await tester.pumpAndSettle();

      expect(
        palette(tester).accent,
        AppPalette.readableOnWhite(CultureVibe.colorOf('ピンク')!),
      );
      expect(backdrop(tester).effect, VibeEffect.sparkle);
      expect(backdrop(tester).running, isFalse);
    });

    testWidgets('「考え中」の段階にも配色が引き継がれる(AC-21)', (tester) async {
      final suggestion = Completer<OutfitSuggestion>();
      final fakes = _Fakes(
        culture: (video) async => report(styles: ['ポップ'], colors: ['水色']),
        outfit: FakeOutfitRepository(suggestResponder: () => suggestion.future),
      );
      await _pump(tester, fakes);
      await _selectMv(tester);
      await _selectLive(tester);
      final accent = palette(tester).accent;
      expect(accent, isNot(AppColors.accent));

      await _press(tester);

      final progress = tester.element(find.text('手持ちの服から、行くライブに合うコーデを考えています'));
      expect(AppPalette.of(progress).accent, accent);
      expect(Theme.of(progress).colorScheme.primary, accent);
      expect(backdrop(tester).effect, VibeEffect.sparkle);

      suggestion.complete(suggestionOf('ポップなコーデ'));
      await _waitResult(tester);
      final result = tester.element(find.text('ポップなコーデ'));
      expect(AppPalette.of(result).accent, accent);
    });
  });

  testWidgets('アプリを起動するとこの画面が出る', (tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('はじめてのライブ服'), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('足りないまま押すと、足りないものを上部に一覧で出し、入力に合わせて消える(AC-6)', (tester) async {
    final fakes = _Fakes(clothes: const []);
    await _pump(tester, fakes);

    await _press(tester);

    expect(find.text('入力内容を確認してください'), findsOneWidget);
    expect(find.text('① で MV を選んでください。'), findsOneWidget);
    expect(find.text('② でライブを検索して、行くライブを選んでください。'), findsOneWidget);
    expect(find.text('③ で手持ちの服を 1 点以上登録してください。'), findsOneWidget);
    expect(fakes.outfit.suggestCalls, isEmpty);
    expect(_phaseSelected(tester, '1 入力'), isTrue);

    await _selectMv(tester);

    expect(find.text('① で MV を選んでください。'), findsNothing);
    expect(find.bySemanticsLabel('MV(OK)'), findsOneWidget);
    expect(find.text('② でライブを検索して、行くライブを選んでください。'), findsOneWidget);
  });

  testWidgets('カルチャー情報の取得中は提案を始めず、待つよう案内する(AC-7)', (tester) async {
    final second = Completer<CultureReport>();
    var calls = 0;
    final fakes = _Fakes(
      culture: (video) =>
          ++calls == 1 ? Future.value(fullReport) : second.future,
    );
    await _pump(tester, fakes);
    await _selectMv(tester);
    await _selectLive(tester);

    // 動画を表示し直すと、カルチャー情報を取得し直す
    await tester.tap(find.byKey(mvSearchButtonKey));
    await tester.pump();
    await tester.pump();
    await _press(tester);

    expect(find.text('カルチャー情報を調べています。終わってからもう一度押してください。'), findsOneWidget);
    expect(fakes.outfit.suggestCalls, isEmpty);

    second.complete(fullReport);
    await tester.pumpAndSettle();
    expect(find.textContaining('カルチャー情報を調べています。'), findsNothing);
  });

  testWidgets('そろえて押すと「AIが考え中」→「提案」と進み、結果を出す(AC-8, AC-10)', (tester) async {
    final suggestion = Completer<OutfitSuggestion>();
    final image = Completer<OutfitImage>();
    final fakes = _Fakes(
      outfit: FakeOutfitRepository(
        suggestResponder: () => suggestion.future,
        imageResponder: (ids) => image.future,
      ),
    );
    await _pump(tester, fakes);
    await _selectMv(tester);
    await _selectLive(tester);

    await _press(tester);

    expect(_phaseSelected(tester, '2 AIが考え中'), isTrue);
    expect(find.text('手持ちの服から、行くライブに合うコーデを考えています'), findsOneWidget);
    // 送信バーと入力のカードは隠れる
    expect(find.text('コーディネートを提案してもらう'), findsNothing);
    expect(find.text('MV を選ぶ'), findsNothing);
    final call = fakes.outfit.suggestCalls.single;
    expect(call.video.videoId, confirmVideo.videoId);
    expect(call.live.liveName, '公演A');
    expect(call.culture?.artist, 'YOASOBI');
    // ライブを選んだときに調べた会場の形態も送る(spec 014)
    expect(fakes.venue.lives.single.liveName, '公演A');
    expect(call.venueFormat, VenueFormat.standing);

    suggestion.complete(suggestionOf('晴れの日のライブコーデ'));
    await tester.pump();
    await tester.pump();
    expect(find.text('マネキンに着せた画像を作っています'), findsOneWidget);
    expect(find.text('コーデに使う服 2点'), findsOneWidget);

    image.complete(OutfitImage(bytes: pngBytes, mimeType: 'image/png'));
    await tester.pump();
    await tester.pump();
    expect(find.text('コーディネートができました!'), findsOneWidget);

    await _waitResult(tester);
    expect(_phaseSelected(tester, '3 提案'), isTrue);
    expect(find.text('晴れの日のライブコーデ'), findsOneWidget);
    expect(find.byKey(const ValueKey('outfit-image')), findsOneWidget);
    expect(find.text('会場・天気'), findsOneWidget);
  });

  testWidgets('キャンセルすると入力に戻り、入力は残り、後から届いた結果では切り替わらない(AC-9)', (tester) async {
    final suggestion = Completer<OutfitSuggestion>();
    final fakes = _Fakes(
      outfit: FakeOutfitRepository(suggestResponder: () => suggestion.future),
    );
    await _pump(tester, fakes);
    await _selectMv(tester);
    await _selectLive(tester);
    await _press(tester);

    await tester.tap(find.text('キャンセルして入力に戻る'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_phaseSelected(tester, '1 入力'), isTrue);
    expect(find.text('提案をキャンセルしました。入力内容はそのまま残っています。'), findsOneWidget);
    // 選んだ動画とライブは残っている
    expect(find.text('YouTube で開く'), findsOneWidget);
    expect(find.byType(CultureSummaryCard), findsOneWidget);
    expect(find.text('公演A'), findsOneWidget);
    expect(find.text('変更'), findsOneWidget);

    suggestion.complete(suggestionOf('届いた提案'));
    await tester.pump();
    await tester.pump(donePause * 2);

    expect(_phaseSelected(tester, '1 入力'), isTrue);
    expect(find.text('届いた提案'), findsNothing);
    expect(fakes.outfit.imageCalls, isEmpty);
  });

  testWidgets('提案が失敗したら入力に戻って理由を出し、もう一度押せる(AC-13)', (tester) async {
    var attempts = 0;
    final fakes = _Fakes(
      outfit: FakeOutfitRepository(
        suggestResponder: () async {
          if (++attempts == 1) {
            throw ApiException(
              '{"detail":"Gemini のクォータ(利用上限)を超えました。"}',
              statusCode: 503,
            );
          }
          return suggestionOf('晴れの日のライブコーデ');
        },
      ),
    );
    await _pump(tester, fakes);
    await _selectMv(tester);
    await _selectLive(tester);

    await _press(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_phaseSelected(tester, '1 入力'), isTrue);
    expect(find.text('コーデを提案できませんでした'), findsOneWidget);
    expect(find.text('Gemini のクォータ(利用上限)を超えました。'), findsOneWidget);
    expect(fakes.outfit.imageCalls, isEmpty);

    await _press(tester);
    await _waitResult(tester);

    expect(find.text('晴れの日のライブコーデ'), findsOneWidget);
    expect(find.text('コーデを提案できませんでした'), findsNothing);
  });

  testWidgets('画像だけ失敗したら、結果の画面で作り直せる(AC-12)', (tester) async {
    var attempts = 0;
    final fakes = _Fakes(
      outfit: FakeOutfitRepository(
        imageResponder: (ids) async {
          if (++attempts == 1) {
            throw ApiException(
              '{"detail":"モデルが画像を返しませんでした。"}',
              statusCode: 502,
            );
          }
          return OutfitImage(bytes: pngBytes, mimeType: 'image/png');
        },
      ),
    );
    await _pump(tester, fakes);
    await _selectMv(tester);
    await _selectLive(tester);
    await _press(tester);
    await _waitResult(tester);

    expect(_phaseSelected(tester, '3 提案'), isTrue);
    expect(find.text('モデルが画像を返しませんでした。'), findsOneWidget);

    await tester.tap(find.text('画像を作り直す'));
    await tester.pumpAndSettle();

    expect(_phaseSelected(tester, '3 提案'), isTrue);
    expect(find.byKey(const ValueKey('outfit-image')), findsOneWidget);
    expect(fakes.outfit.suggestCalls, hasLength(1));
    expect(fakes.outfit.imageCalls, hasLength(2));
  });

  testWidgets('「条件を変えてもう一度」で入力に戻り、入力は残り、押し直すと結果が置き換わる(AC-14)', (tester) async {
    final titles = ['1 回目のコーデ', '2 回目のコーデ'];
    final fakes = _Fakes(
      outfit: FakeOutfitRepository(
        suggestResponder: () async => suggestionOf(titles.removeAt(0)),
      ),
    );
    await _pump(tester, fakes);
    await _selectMv(tester);
    await _selectLive(tester);
    await _press(tester);
    await _waitResult(tester);
    expect(find.text('1 回目のコーデ'), findsOneWidget);

    await tester.tap(find.text('条件を変えてもう一度'));
    await tester.pumpAndSettle();

    expect(_phaseSelected(tester, '1 入力'), isTrue);
    expect(find.text('公演A'), findsOneWidget);
    expect(find.bySemanticsLabel('MV(OK)'), findsOneWidget);

    await _press(tester);
    await _waitResult(tester);

    expect(find.text('2 回目のコーデ'), findsOneWidget);
    expect(find.text('1 回目のコーデ'), findsNothing);
  });

  testWidgets('幅 390px の縦画面でも、各段階ではみ出さない(AC-17)', (tester) async {
    final fakes = _Fakes();
    await _pump(tester, fakes, size: const Size(390, 6000));
    await _selectMv(tester);
    await _selectLive(tester);
    expect(tester.takeException(), isNull);

    await _press(tester);
    expect(tester.takeException(), isNull);

    await _waitResult(tester);
    expect(find.text('晴れの日のライブコーデ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
