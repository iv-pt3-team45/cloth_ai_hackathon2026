import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/features/wardrobe/photo_picker.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_models.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_section.dart';

import 'wardrobe_fakes.dart';

/// ③ のカードから「写真を選ぶ」で確認画面を開く。
Future<void> _openReview(
  WidgetTester tester,
  FakeWardrobeRepository repo,
  List<PickedPhoto> photos,
) async {
  // 写真と編集欄が一度に描画されるよう、画面を縦に長くする
  tester.view.physicalSize = const Size(1400, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WardrobeSection(
            repository: repo,
            picker: FakePhotoPicker(photos),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('写真を選ぶ'));
  // 解析中はプログレスが回り続けるため pumpAndSettle は使わない
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

ButtonStyleButton _button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  testWidgets('1 枚ずつ順に解析し、何枚目かが分かる(AC-2)', (tester) async {
    final pending = {
      'a.png': Completer<ClothAnalysis>(),
      'b.png': Completer<ClothAnalysis>(),
    };
    final repo = FakeWardrobeRepository(
      analyzeResponder: (photo) => pending[photo.name]!.future,
    );
    await _openReview(tester, repo, [photo('a.png'), photo('b.png')]);

    expect(find.text('解析中 1 / 2'), findsOneWidget);
    // 同時には解析しない
    expect(repo.analyzed, ['a.png']);

    pending['a.png']!.complete(const ClothAnalysis(items: [shirt]));
    await tester.pump();
    await tester.pump();
    expect(find.text('解析中 2 / 2'), findsOneWidget);
    expect(repo.analyzed, ['a.png', 'b.png']);

    pending['b.png']!.complete(const ClothAnalysis(items: [jeans]));
    await tester.pumpAndSettle();

    expect(find.textContaining('解析中'), findsNothing);
    expect(find.text('2 点を保存'), findsOneWidget);
  });

  testWidgets('複数の服を分けて表示し、直して・外して保存できる(AC-3, AC-4, AC-5, AC-6)', (
    tester,
  ) async {
    final repo = FakeWardrobeRepository(
      analyzeResponder: (photo) async => photo.name == 'a.png'
          ? const ClothAnalysis(items: [shirt, jeans], summary: '2 点')
          : const ClothAnalysis(items: [shirt]),
    );
    await _openReview(tester, repo, [photo('a.png'), photo('b.png')]);
    await tester.pumpAndSettle();

    // 1 枚目の 2 点と 2 枚目の 1 点が分かれて並ぶ
    expect(_field('種類'), findsNWidgets(3));

    // 1 枚目の服 1 を直す
    await tester.enterText(_field('種類').first, 'ロングTシャツ');
    await tester.tap(find.widgetWithText(FilterChip, '冬').first);
    await tester.tap(find.widgetWithText(ChoiceChip, '厚手').first);
    await tester.tap(find.widgetWithText(FilterChip, 'ライブ・フェス').first);
    // 1 枚目の服 2 を外し、2 枚目の写真を丸ごと外す
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();

    expect(find.text('1 点を保存'), findsOneWidget);
    await tester.tap(find.text('1 点を保存'));
    await tester.pumpAndSettle();

    expect(repo.registered, hasLength(1));
    final call = repo.registered.single;
    expect(call.photo.name, 'a.png');
    expect(call.summary, '2 点');
    final saved = call.items.single;
    expect(saved.category, 'ロングTシャツ');
    expect(saved.seasons, ['春', '夏', '冬']);
    expect(saved.warmth, '厚手');
    expect(saved.occasions, ['普段着', 'ライブ・フェス']);
    // ③ のカードに戻り、保存した服が出る
    expect(find.text('写真を選ぶ'), findsOneWidget);
    expect(find.text('ロングTシャツ'), findsOneWidget);
  });

  testWidgets('保存せずに取りやめると何も保存されない(AC-7)', (tester) async {
    final repo = FakeWardrobeRepository();
    await _openReview(tester, repo, [photo('a.png')]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.text('保存せずに戻りますか？'), findsOneWidget);

    // 「確認を続ける」なら画面に残る
    await tester.tap(find.text('確認を続ける'));
    await tester.pumpAndSettle();
    expect(find.text('写真の確認'), findsOneWidget);

    await tester.tap(find.byTooltip('キャンセル'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存せずに戻る'));
    await tester.pumpAndSettle();

    expect(repo.registered, isEmpty);
    expect(find.text('写真を選ぶ'), findsOneWidget);
    expect(find.textContaining('まだ服が登録されていません'), findsOneWidget);
  });

  testWidgets('形式が対応外・服が写っていない写真だけエラーになり、他は続く(AC-11)', (tester) async {
    final repo = FakeWardrobeRepository(
      analyzeResponder: (photo) async => photo.name == 'empty.png'
          ? const ClothAnalysis()
          : const ClothAnalysis(items: [shirt]),
    );
    await _openReview(tester, repo, [
      photo('bad.heic', mimeType: null),
      photo('empty.png'),
      photo('good.png'),
    ]);
    await tester.pumpAndSettle();

    // 対応外の形式は API を呼ばない
    expect(repo.analyzed, ['empty.png', 'good.png']);
    expect(find.textContaining('対応していない形式です'), findsOneWidget);
    expect(find.textContaining('服が写っていないようです'), findsOneWidget);
    expect(find.text('1 点を保存'), findsOneWidget);
  });

  testWidgets('Gemini の失敗はその写真にエラーと再解析を出す(AC-12)', (tester) async {
    var attempts = 0;
    final repo = FakeWardrobeRepository(
      analyzeResponder: (photo) async {
        attempts++;
        if (attempts == 1) {
          throw ApiException(
            '{"detail":"Gemini のクォータ(利用上限)を超えました。"}',
            statusCode: 503,
          );
        }
        return const ClothAnalysis(items: [shirt]);
      },
    );
    await _openReview(tester, repo, [photo('a.png')]);
    await tester.pumpAndSettle();

    expect(find.text('Gemini のクォータ(利用上限)を超えました。'), findsOneWidget);
    expect(find.text('保存する服がありません'), findsOneWidget);

    await tester.tap(find.text('再解析'));
    await tester.pumpAndSettle();

    expect(repo.analyzed, ['a.png', 'a.png']);
    expect(find.text('1 点を保存'), findsOneWidget);
  });

  testWidgets('大きすぎる写真は再解析しても直らないため再解析を出さない(AC-11)', (tester) async {
    final repo = FakeWardrobeRepository(
      analyzeResponder: (photo) async => throw ApiException(
        '{"detail":"写真が大きすぎます。10 MB 以下の写真を選んでください。"}',
        statusCode: 413,
      ),
    );
    await _openReview(tester, repo, [photo('big.png')]);
    await tester.pumpAndSettle();

    expect(find.textContaining('写真が大きすぎます'), findsOneWidget);
    expect(find.text('再解析'), findsNothing);
  });

  testWidgets('種類が空の服があれば保存できない', (tester) async {
    await _openReview(tester, FakeWardrobeRepository(), [photo('a.png')]);
    await tester.pumpAndSettle();

    await tester.enterText(_field('種類'), '  ');
    await tester.pump();

    expect(find.textContaining('種類が空の服があります'), findsOneWidget);
    expect(_button(tester, '1 点を保存').enabled, isFalse);
  });

  testWidgets('保存に失敗したら確認画面に残ってエラーを出す', (tester) async {
    final repo = FakeWardrobeRepository(
      registerErrors: {
        'a.png': ApiException('{"detail":"保存先に書き込めません"}', statusCode: 502),
      },
    );
    await _openReview(tester, repo, [photo('a.png')]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('1 点を保存'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('「a.png」を保存できませんでした: 保存先に書き込めません'),
      findsOneWidget,
    );
    expect(find.text('写真の確認'), findsOneWidget);
  });

  testWidgets('11 枚以上選んだら先頭 10 枚だけを使う', (tester) async {
    final repo = FakeWardrobeRepository();
    await _openReview(tester, repo, [
      for (var i = 0; i < 12; i++) photo('p$i.png'),
    ]);
    await tester.pumpAndSettle();

    expect(repo.analyzed, hasLength(maxPhotosPerBatch));
    expect(find.text('$maxPhotosPerBatch 点を保存'), findsOneWidget);
  });
}
