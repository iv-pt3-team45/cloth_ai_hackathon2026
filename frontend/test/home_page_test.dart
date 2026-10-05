import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/app/home_page.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/core/theme.dart';
import 'package:tx_hackathon_gc/core/widgets.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_section.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_panel.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';
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
         (query) async =>
             const MvLookupResult(inputType: 'url', video: confirmVideo),
       ),
       culture = FakeCultureRepository(culture ?? (video) async => fullReport),
       live = FakeLiveRepository(),
       wardrobe = FakeWardrobeRepository(items: clothes),
       outfit = outfit ?? FakeOutfitRepository();

  final FakeMvRepository mv;
  final FakeCultureRepository culture;
  final FakeLiveRepository live;
  final FakeWardrobeRepository wardrobe;
  final FakeOutfitRepository outfit;
}

Future<void> _pump(
  WidgetTester tester,
  _Fakes fakes, {
  Size size = const Size(1200, 6000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: HomePage(
        mvRepository: fakes.mv,
        cultureRepository: fakes.culture,
        liveRepository: fakes.live,
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
    expect(
      find.text('https://www.youtube.com/watch?v=abcDEF12345'),
      findsWidgets,
    );
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
