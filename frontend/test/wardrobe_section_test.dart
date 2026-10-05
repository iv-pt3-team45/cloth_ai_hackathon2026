import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/core/theme.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_models.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_section.dart';

import 'wardrobe_fakes.dart';

const _registered = RegisteredCloth(
  id: 'id1',
  image: 'cloth-1.jpg',
  attributes: ClothAttributes(
    category: 'Tシャツ',
    material: '綿',
    shape: '半袖',
    colors: ['白', '紺'],
    style: 'カジュアル',
    seasons: ['春', '夏'],
    warmth: '薄手',
    occasions: ['普段着', 'きれいめ'],
  ),
);

Future<List<List<RegisteredCloth>?>> _pump(
  WidgetTester tester,
  FakeWardrobeRepository repo,
) async {
  final changes = <List<RegisteredCloth>?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: WardrobeSection(
            repository: repo,
            picker: FakePhotoPicker([]),
            onChanged: changes.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return changes;
}

void main() {
  testWidgets('「③ 手持ちの服」のカードで、0 件なら登録を促す(spec 010 AC-8 / spec 015)', (
    tester,
  ) async {
    final changes = await _pump(tester, FakeWardrobeRepository());

    expect(find.text('手持ちの服'), findsOneWidget);
    expect(find.text('0 点'), findsOneWidget);
    expect(find.textContaining('まだ服が登録されていません'), findsOneWidget);
    expect(find.text('写真を選ぶ'), findsOneWidget);
    expect(changes.last, isEmpty);
  });

  testWidgets('登録済みの服を写真の格子で並べ、タップで属性を見られる(spec 010 AC-8)', (tester) async {
    final changes = await _pump(
      tester,
      FakeWardrobeRepository(items: [_registered]),
    );

    expect(find.text('1 点'), findsOneWidget);
    expect(find.byKey(const ValueKey('cloth-id1')), findsOneWidget);
    // 写真を読み込めない場合もプレースホルダを出す
    expect(find.byIcon(Icons.checkroom), findsOneWidget);
    expect(changes.last?.single.id, 'id1');
    // 属性は一覧には出さず、タップしたシートで見る
    expect(find.text('色: 白・紺'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cloth-id1')));
    await tester.pumpAndSettle();

    expect(find.text('色: 白・紺'), findsOneWidget);
    expect(find.text('素材: 綿 / 形: 半袖'), findsOneWidget);
    expect(find.text('系統: カジュアル'), findsOneWidget);
    expect(find.text('季節: 春・夏 / 暖かさ: 薄手'), findsOneWidget);
    expect(find.text('場面: 普段着・きれいめ(食事・オフィス)'), findsOneWidget);
  });

  testWidgets('確認のうえで削除でき、一覧から消える(spec 010 AC-9)', (tester) async {
    final repo = FakeWardrobeRepository(items: [_registered]);
    final changes = await _pump(tester, repo);

    // キャンセルすれば消さない
    await tester.tap(find.byTooltip('削除'));
    await tester.pumpAndSettle();
    expect(find.text('この服を削除しますか？'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);

    await tester.tap(find.byTooltip('削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '削除'));
    await tester.pumpAndSettle();

    expect(repo.deleted, ['id1']);
    expect(find.byKey(const ValueKey('cloth-id1')), findsNothing);
    expect(find.text('削除しました'), findsOneWidget);
    expect(changes.last, isEmpty);
  });

  testWidgets('一覧を読み込めなければエラーと再読み込みを出す', (tester) async {
    final repo = FakeWardrobeRepository(
      listError: ApiException('{"detail":"読み込みに失敗しました"}', statusCode: 502),
    );
    await _pump(tester, repo);

    expect(find.text('読み込みに失敗しました'), findsOneWidget);

    repo.listError = null;
    await tester.tap(find.widgetWithText(TextButton, '再読み込み'));
    await tester.pumpAndSettle();

    expect(find.textContaining('まだ服が登録されていません'), findsOneWidget);
  });
}
