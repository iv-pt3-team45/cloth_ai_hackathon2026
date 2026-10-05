import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_snapshot.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/venue_models.dart';
import 'package:tx_hackathon_gc/features/outfit/confirm_screen.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_models.dart';
import 'package:tx_hackathon_gc/features/outfit/wardrobe_strip.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_models.dart';

import 'outfit_fakes.dart';
import 'wardrobe_fakes.dart';

Widget _screen(
  ValueNotifier<MvLookupSnapshot> snapshot,
  FakeWardrobeRepository wardrobe,
  FakeOutfitRepository outfit, {
  bool active = true,
}) => MaterialApp(
  home: ConfirmScreen(
    snapshot: snapshot,
    active: active,
    wardrobeRepository: wardrobe,
    outfitRepository: outfit,
  ),
);

Future<ValueNotifier<MvLookupSnapshot>> _pump(
  WidgetTester tester, {
  MvLookupSnapshot snapshot = const MvLookupSnapshot(),
  FakeWardrobeRepository? wardrobe,
  FakeOutfitRepository? outfit,
}) async {
  // すべての欄が一度に描画されるよう、画面を縦に長くする
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final notifier = ValueNotifier(snapshot);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    _screen(
      notifier,
      wardrobe ?? FakeWardrobeRepository(items: [ownedShirt]),
      outfit ?? FakeOutfitRepository(),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

ButtonStyleButton _button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );

void main() {
  testWidgets('まだ何も無ければ案内を出し、提案は押せない(AC-6, AC-8)', (tester) async {
    await _pump(tester, wardrobe: FakeWardrobeRepository());

    expect(find.text('まだありません(MV 検索タブで入力してください)'), findsOneWidget);
    expect(find.text('まだありません(MV 検索タブで動画を表示してください)'), findsNWidgets(2));
    expect(find.textContaining('「ライブを探す」で選んでください'), findsOneWidget);
    expect(find.text('まだありません(手持ちの服タブで登録してください)'), findsOneWidget);
    expect(find.text('足りないもの: 手持ちの服 / MV / ライブの選択'), findsOneWidget);
    expect(_button(tester, 'コーデを提案').enabled, isFalse);
  });

  testWidgets('他のタブの情報をまとめて表示する(AC-2, AC-3, AC-4, AC-5)', (tester) async {
    await _pump(tester, snapshot: fullSnapshot());

    // 入力
    expect(find.text('MV: アイドル'), findsOneWidget);
    expect(find.text('ライブ: 電光石火 / 2023/06/04'), findsOneWidget);
    // MV 情報とアーティスト情報
    expect(find.text('アイドル'), findsOneWidget);
    expect(
      find.text('https://www.youtube.com/watch?v=abcDEF12345'),
      findsOneWidget,
    );
    expect(find.text('小説を音楽にするユニット'), findsOneWidget);
    // カルチャー情報: MV のファッションと音楽ジャンル
    for (final chip in ['ストリート', '黒', 'ベレー帽', 'J-POP']) {
      expect(find.widgetWithText(Chip, chip), findsOneWidget);
    }
    expect(find.text('・メインの衣装: ワンピース(白)'), findsOneWidget);
    // ライブ情報と天気
    expect(find.text('公演A'), findsOneWidget);
    expect(find.text('場所: さいたまスーパーアリーナ(埼玉県さいたま市)'), findsOneWidget);
    expect(find.text('天気: 晴れ / 最高 27℃ / 最低 18℃(実績)'), findsOneWidget);
    // グラウンディング結果には検索候補を添える(Web 以外では検索クエリ)
    expect(find.widgetWithText(Chip, 'YOASOBI ファッション'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'YOASOBI ライブ 2023'), findsOneWidget);
    // 手持ちの服の横並び
    expect(find.text('1 点'), findsOneWidget);
    expect(find.byKey(const ValueKey('strip-shirt')), findsOneWidget);
    expect(_button(tester, 'コーデを提案').enabled, isTrue);
  });

  testWidgets('他のタブで内容が変わると反映される(AC-7)', (tester) async {
    final notifier = await _pump(tester, snapshot: fullSnapshot());

    final lives = fullSnapshot().liveResult!;
    notifier.value = fullSnapshot(selectedLive: lives.candidates[1]);
    await tester.pumpAndSettle();

    expect(find.text('公演B'), findsOneWidget);
    expect(find.text('公演A'), findsNothing);
  });

  testWidgets('確認タブを開くと手持ちの服を読み直す(AC-7)', (tester) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notifier = ValueNotifier(fullSnapshot());
    addTearDown(notifier.dispose);
    final wardrobe = FakeWardrobeRepository();
    final outfit = FakeOutfitRepository();
    await tester.pumpWidget(_screen(notifier, wardrobe, outfit, active: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('手持ちの服タブで登録してください'), findsOneWidget);

    // 手持ちの服タブで登録してから、確認タブを開く
    wardrobe.items.add(ownedShirt);
    await tester.pumpWidget(_screen(notifier, wardrobe, outfit));
    await tester.pumpAndSettle();

    expect(find.text('1 点'), findsOneWidget);
  });

  test('1 画面に並ぶ枚数は画面の幅で決まる(AC-5)', () {
    expect(itemsPerScreen(390), 4);
    expect(itemsPerScreen(600), 6);
    expect(itemsPerScreen(1023), 6);
    expect(itemsPerScreen(1440), 8);
  });

  testWidgets('横並びは 1 画面の枚数がちょうど収まる幅になり、横にスクロールできる(AC-5)', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final items = [
      for (var i = 0; i < 12; i++)
        RegisteredCloth(id: 'c$i', image: '', attributes: shirt),
    ];
    Future<double> itemWidth(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: WardrobeStrip(items: items, imageUrl: (_) => ''),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(const ValueKey('strip-c0'))).width;
    }

    // スマホ幅は 4 枚、PC 幅は 8 枚(間隔 8px)
    expect(await itemWidth(400), (400 - 8 * 3) / 4);
    expect(await itemWidth(1200), (1200 - 8 * 7) / 8);
    // 1 画面に収まらない分は横にスクロールして見る
    expect(find.byKey(const ValueKey('strip-c11')), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('strip-c11')), findsOneWidget);
  });

  testWidgets('提案すると手持ちの服のコーデと、着せた画像が出る(AC-9, AC-10, AC-11)', (tester) async {
    final outfit = FakeOutfitRepository();
    await _pump(tester, snapshot: fullSnapshot(), outfit: outfit);

    await tester.tap(find.text('コーデを提案'));
    await tester.pumpAndSettle();

    final call = outfit.suggestCalls.single;
    expect(call.video.videoId, 'abcDEF12345');
    expect(call.live.liveName, '公演A');
    expect(call.culture?.artist, 'YOASOBI');
    expect(find.text('晴れの日のライブコーデ'), findsOneWidget);
    expect(find.text('・トップス: Tシャツ — 白で合わせやすい'), findsOneWidget);
    expect(find.text('・ボトムス: ジーンズ — 動きやすい'), findsOneWidget);
    expect(find.text('・晴れで暑いため薄手'), findsOneWidget);
    expect(find.text('手持ちに無い服 1 点は提案から除きました'), findsOneWidget);
    // 提案の服で画像を生成する
    expect(outfit.imageCalls, [
      ['shirt', 'jeans'],
    ]);
    expect(find.byKey(const ValueKey('outfit-image')), findsOneWidget);
  });

  testWidgets('ライブ情報欄に客席の形態を出す(spec 014)', (tester) async {
    final notifier = await _pump(
      tester,
      snapshot: fullSnapshot(venueFormatLoading: true),
    );
    expect(find.text('客席: 調べています…'), findsOneWidget);

    notifier.value = fullSnapshot(venueFormat: VenueFormat.standing);
    await tester.pump();
    expect(find.text('客席: スタンディング(立ち見)'), findsOneWidget);

    notifier.value = fullSnapshot(venueFormat: VenueFormat.mixed);
    await tester.pump();
    expect(find.text('客席: スタンディングと着席の両方あり(チケットによって異なる)'), findsOneWidget);

    notifier.value = fullSnapshot();
    await tester.pump();
    expect(find.text('客席: 不明'), findsOneWidget);
  });

  testWidgets('提案のとき、調べ終わった会場の形態を一緒に送る(spec 014)', (tester) async {
    final outfit = FakeOutfitRepository();
    await _pump(
      tester,
      snapshot: fullSnapshot(venueFormat: VenueFormat.seated),
      outfit: outfit,
    );

    await tester.tap(find.text('コーデを提案'));
    await tester.pumpAndSettle();

    expect(outfit.suggestCalls.single.venueFormat, VenueFormat.seated);
  });

  testWidgets('会場の形態を調べている途中なら送らない(spec 014)', (tester) async {
    final outfit = FakeOutfitRepository();
    await _pump(
      tester,
      snapshot: fullSnapshot(
        venueFormat: VenueFormat.seated,
        venueFormatLoading: true,
      ),
      outfit: outfit,
    );

    await tester.tap(find.text('コーデを提案'));
    await tester.pumpAndSettle();

    expect(outfit.suggestCalls.single.venueFormat, isNull);
  });

  testWidgets('提案・画像の生成中はローディングを出し、押せない(AC-12)', (tester) async {
    final suggestion = Completer<OutfitSuggestion>();
    final image = Completer<OutfitImage>();
    final outfit = FakeOutfitRepository(
      suggestResponder: () => suggestion.future,
      imageResponder: (ids) => image.future,
    );
    await _pump(tester, snapshot: fullSnapshot(), outfit: outfit);

    await tester.tap(find.text('コーデを提案'));
    await tester.pump();
    expect(find.textContaining('コーデを考えています'), findsOneWidget);
    expect(_button(tester, 'コーデを提案').enabled, isFalse);

    suggestion.complete(suggestionOf('晴れの日のライブコーデ'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('画像を作っています'), findsOneWidget);
    expect(_button(tester, 'コーデを提案').enabled, isFalse);

    image.complete(OutfitImage(bytes: pngBytes, mimeType: 'image/png'));
    await tester.pumpAndSettle();
    expect(_button(tester, 'コーデを提案').enabled, isTrue);
  });

  testWidgets('画像だけ失敗したら提案を残し、作り直せる(AC-13)', (tester) async {
    var attempts = 0;
    final outfit = FakeOutfitRepository(
      imageResponder: (ids) async {
        attempts++;
        if (attempts == 1) {
          throw ApiException('{"detail":"モデルが画像を返しませんでした。"}', statusCode: 502);
        }
        return OutfitImage(bytes: pngBytes, mimeType: 'image/png');
      },
    );
    await _pump(tester, snapshot: fullSnapshot(), outfit: outfit);

    await tester.tap(find.text('コーデを提案'));
    await tester.pumpAndSettle();

    expect(find.text('晴れの日のライブコーデ'), findsOneWidget);
    expect(find.text('モデルが画像を返しませんでした。'), findsOneWidget);

    await tester.tap(find.text('画像を作り直す'));
    await tester.pumpAndSettle();

    expect(outfit.suggestCalls, hasLength(1));
    expect(outfit.imageCalls, hasLength(2));
    expect(find.byKey(const ValueKey('outfit-image')), findsOneWidget);
  });

  testWidgets('提案に失敗したらエラーと再試行を出す(AC-13)', (tester) async {
    var attempts = 0;
    final outfit = FakeOutfitRepository(
      suggestResponder: () async {
        attempts++;
        if (attempts == 1) {
          throw ApiException(
            '{"detail":"Gemini のクォータ(利用上限)を超えました。"}',
            statusCode: 503,
          );
        }
        return suggestionOf('晴れの日のライブコーデ');
      },
    );
    await _pump(tester, snapshot: fullSnapshot(), outfit: outfit);

    await tester.tap(find.text('コーデを提案'));
    await tester.pumpAndSettle();
    expect(find.text('Gemini のクォータ(利用上限)を超えました。'), findsOneWidget);
    expect(outfit.imageCalls, isEmpty);

    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();

    expect(find.text('晴れの日のライブコーデ'), findsOneWidget);
  });

  testWidgets('押し直すと新しい提案に置き換わる(AC-14)', (tester) async {
    final titles = ['1 回目のコーデ', '2 回目のコーデ'];
    final outfit = FakeOutfitRepository(
      suggestResponder: () async => suggestionOf(titles.removeAt(0)),
    );
    await _pump(tester, snapshot: fullSnapshot(), outfit: outfit);

    await tester.tap(find.text('コーデを提案'));
    await tester.pumpAndSettle();
    expect(find.text('1 回目のコーデ'), findsOneWidget);

    await tester.tap(find.text('コーデを提案'));
    await tester.pumpAndSettle();

    expect(find.text('2 回目のコーデ'), findsOneWidget);
    expect(find.text('1 回目のコーデ'), findsNothing);
    expect(outfit.imageCalls, hasLength(2));
  });

  testWidgets('カルチャー情報の取得中は提案を押せない', (tester) async {
    final snapshot = fullSnapshot();
    await _pump(
      tester,
      snapshot: MvLookupSnapshot(
        mvQuery: snapshot.mvQuery,
        video: snapshot.video,
        cultureLoading: true,
        liveResult: snapshot.liveResult,
        selectedLive: snapshot.selectedLive,
      ),
    );

    expect(find.text('カルチャー情報の取得が終わるまでお待ちください'), findsOneWidget);
    expect(_button(tester, 'コーデを提案').enabled, isFalse);
  });
}
