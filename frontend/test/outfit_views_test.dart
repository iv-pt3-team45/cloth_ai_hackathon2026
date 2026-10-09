import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/theme.dart';
import 'package:tx_hackathon_gc/core/widgets.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_controller.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_models.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_progress_view.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_result_view.dart';

import 'outfit_fakes.dart';
import 'wardrobe_fakes.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _progress(
  WidgetTester tester,
  OutfitStage stage, {
  DateTime? startedAt,
  VoidCallback? onCancel,
}) async {
  _tall(tester);
  // イコライザーは止まらないアニメーションのため pumpAndSettle は使わない
  await tester.pumpWidget(
    _app(
      OutfitProgressView(
        stage: stage,
        startedAt: startedAt ?? DateTime.now(),
        clothes: const [ownedShirt, ownedJeans],
        photo: fakePhoto,
        onCancel: onCancel ?? () {},
      ),
    ),
  );
  await tester.pump();
}

Future<void> _result(
  WidgetTester tester, {
  OutfitImage? image,
  String? imageError,
  bool retrying = false,
  bool canSave = false,
  VoidCallback? onRetryImage,
  VoidCallback? onRestart,
}) async {
  _tall(tester);
  final snapshot = fullSnapshot();
  await tester.pumpWidget(
    _app(
      OutfitResultView(
        suggestion: suggestionOf('晴れの日のライブコーデ', excluded: 1),
        image: image,
        imageError: imageError,
        retryingImage: retrying,
        live: snapshot.selectedLive,
        liveResult: snapshot.liveResult,
        culture: snapshot.culture,
        photo: fakePhoto,
        canSave: canSave,
        onRetryImage: onRetryImage ?? () {},
        onRestart: onRestart ?? () {},
      ),
    ),
  );
  await tester.pump();
}

final _image = OutfitImage(bytes: pngBytes, mimeType: 'image/png');

void main() {
  testWidgets('考えている間は段階 1 が処理中で、経過時間とキャンセルを出す(spec 015 AC-8, AC-9)', (
    tester,
  ) async {
    var cancelled = 0;
    await _progress(
      tester,
      OutfitStage.suggesting,
      onCancel: () => cancelled++,
    );

    expect(find.text('手持ちの服から、行くライブに合うコーデを考えています'), findsOneWidget);
    expect(find.bySemanticsLabel('コーデを考える(処理中)'), findsOneWidget);
    expect(find.bySemanticsLabel('着せた画像を作る(これから)'), findsOneWidget);
    expect(find.text('経過 0秒 ・ 目安 30秒〜1分'), findsOneWidget);
    expect(find.text('手持ちの服 2点から選んでいます'), findsOneWidget);
    // 進み具合の % は出さない(要件の決定事項 8)
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('%'), findsNothing);

    await tester.tap(find.text('キャンセルして入力に戻る'));
    expect(cancelled, 1);
  });

  testWidgets('画像を作る間は段階 2 が処理中になる', (tester) async {
    await _progress(tester, OutfitStage.imaging);

    expect(find.text('マネキンに着せた画像を作っています'), findsOneWidget);
    expect(find.bySemanticsLabel('コーデを考える(完了)'), findsOneWidget);
    expect(find.bySemanticsLabel('着せた画像を作る(処理中)'), findsOneWidget);
    expect(find.text('コーデに使う服 2点'), findsOneWidget);
  });

  testWidgets('終わったら「できました」を出し、キャンセルは出さない', (tester) async {
    await _progress(tester, OutfitStage.done);

    expect(find.text('コーディネートができました!'), findsOneWidget);
    expect(find.bySemanticsLabel('着せた画像を作る(完了)'), findsOneWidget);
    expect(find.text('キャンセルして入力に戻る'), findsNothing);
  });

  testWidgets('画像だけ失敗して終わったときは、そう知らせる', (tester) async {
    _tall(tester);
    await tester.pumpWidget(
      _app(
        OutfitProgressView(
          stage: OutfitStage.done,
          startedAt: DateTime.now(),
          clothes: const [ownedShirt],
          photo: fakePhoto,
          onCancel: () {},
          imageFailed: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('コーデはできましたが、画像は作れませんでした'), findsOneWidget);
    expect(find.bySemanticsLabel('着せた画像を作る(失敗)'), findsOneWidget);
    expect(find.text('コーディネートができました!'), findsNothing);
  });

  testWidgets('長くかかっているときは知らせる', (tester) async {
    await _progress(
      tester,
      OutfitStage.imaging,
      startedAt: DateTime.now().subtract(const Duration(seconds: 160)),
    );

    expect(find.text('経過 2分40秒 ・ 目安 30秒〜1分'), findsOneWidget);
    expect(find.textContaining('いつもより時間がかかっています'), findsOneWidget);
  });

  testWidgets('結果にはコーデ名・画像・使う服・理由・提案に使った情報を出す(spec 015 AC-10)', (tester) async {
    var restarted = 0;
    await _result(tester, image: _image, onRestart: () => restarted++);

    expect(find.text('公演A ・ 2023/06/04 ・ さいたまスーパーアリーナ'), findsOneWidget);
    expect(find.text('晴れの日のライブコーデ'), findsOneWidget);
    expect(find.byKey(const ValueKey('outfit-image')), findsOneWidget);
    // 使う服(役割・種類・理由)
    expect(find.text('トップス'), findsOneWidget);
    expect(find.text('Tシャツ'), findsOneWidget);
    expect(find.text('白で合わせやすい'), findsOneWidget);
    expect(find.text('手持ちに無い服 1 点は提案から除きました'), findsOneWidget);
    // 選んだ理由
    expect(find.text('このコーデを選んだ理由'), findsOneWidget);
    expect(find.text('動きやすいカジュアル'), findsOneWidget);
    expect(find.text('晴れで暑いため薄手'), findsOneWidget);
    // 提案に使った情報(グラウンディングの結果なので出典と検索候補も添える)
    expect(find.text('MV のファッション'), findsOneWidget);
    for (final value in ['ストリート', '黒', 'ベレー帽', 'J-POP']) {
      expect(find.widgetWithText(Pill, value), findsOneWidget);
    }
    expect(find.text('会場・天気'), findsOneWidget);
    expect(find.text('天気: 晴れ / 最高 27℃ / 最低 18℃(実績)'), findsOneWidget);
    expect(find.text('参照した情報源:'), findsNWidgets(2));

    await tester.tap(find.text('条件を変えてもう一度'));
    expect(restarted, 1);
  });

  testWidgets('画像をタップすると全画面で拡大する(spec 015 AC-11)', (tester) async {
    await _result(tester, image: _image);

    await tester.tap(find.byKey(const ValueKey('outfit-image')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('outfit-image-zoom')), findsOneWidget);

    await tester.tap(find.byTooltip('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('outfit-image-zoom')), findsNothing);
  });

  testWidgets('「画像を保存」は Web でだけ出す(spec 015 AC-11)', (tester) async {
    await _result(tester, image: _image);
    expect(find.text('拡大して見る'), findsOneWidget);
    expect(find.text('画像を保存'), findsNothing);

    await _result(tester, image: _image, canSave: true);
    expect(find.text('画像を保存'), findsOneWidget);
  });

  testWidgets('画像だけ失敗したら、提案は出したまま作り直せる(spec 015 AC-12)', (tester) async {
    var retried = 0;
    await _result(
      tester,
      imageError: 'モデルが画像を返しませんでした。',
      onRetryImage: () => retried++,
    );

    expect(find.text('晴れの日のライブコーデ'), findsOneWidget);
    expect(find.text('モデルが画像を返しませんでした。'), findsOneWidget);

    await tester.tap(find.text('画像を作り直す'));
    expect(retried, 1);

    await _result(tester, retrying: true);
    expect(find.textContaining('マネキンに着せた画像を作っています'), findsOneWidget);
    expect(find.text('画像を作り直す'), findsNothing);
  });
}
