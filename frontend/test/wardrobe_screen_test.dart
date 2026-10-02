import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_models.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_screen.dart';
import 'package:tx_hackathon_gc/main.dart';

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

Future<void> _pump(WidgetTester tester, FakeWardrobeRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: WardrobeScreen(repository: repo, picker: FakePhotoPicker([])),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('MV 検索・チャットとは別に「手持ちの服」タブがある(AC-1)', (tester) async {
    await tester.pumpWidget(const App());

    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label);
    // spec 011 で「確認」タブが加わった
    expect(labels, ['MV 検索', '手持ちの服', '確認', 'チャット']);
    expect(find.text('写真を追加'), findsNothing);

    await tester.tap(find.text('手持ちの服'));
    await tester.pumpAndSettle();

    expect(find.text('写真を追加'), findsOneWidget);
  });

  testWidgets('0 件なら登録を促す(AC-8)', (tester) async {
    await _pump(tester, FakeWardrobeRepository());

    expect(find.textContaining('まだ服が登録されていません'), findsOneWidget);
  });

  testWidgets('登録済みの服を写真と主な属性で一覧表示する(AC-8)', (tester) async {
    await _pump(tester, FakeWardrobeRepository(items: [_registered]));

    expect(find.text('Tシャツ'), findsOneWidget);
    expect(find.text('色: 白・紺'), findsOneWidget);
    expect(find.text('素材: 綿 / 形: 半袖'), findsOneWidget);
    expect(find.text('系統: カジュアル'), findsOneWidget);
    expect(find.text('季節: 春・夏 / 暖かさ: 薄手'), findsOneWidget);
    expect(find.text('場面: 普段着・きれいめ(食事・オフィス)'), findsOneWidget);
    // 写真を読み込めない場合もプレースホルダを出す
    expect(find.byIcon(Icons.checkroom), findsOneWidget);
  });

  testWidgets('確認のうえで削除でき、一覧から消える(AC-9)', (tester) async {
    final repo = FakeWardrobeRepository(items: [_registered]);
    await _pump(tester, repo);

    // キャンセルすれば消さない
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('この服を削除しますか？'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '削除'));
    await tester.pumpAndSettle();

    expect(repo.deleted, ['id1']);
    expect(find.text('Tシャツ'), findsNothing);
    expect(find.text('削除しました'), findsOneWidget);
  });

  testWidgets('一覧を読み込めなければエラーと再読み込みを出す', (tester) async {
    final repo = FakeWardrobeRepository(
      listError: ApiException('{"detail":"読み込みに失敗しました"}', statusCode: 502),
    );
    await _pump(tester, repo);

    expect(find.text('読み込みに失敗しました'), findsOneWidget);

    repo.listError = null;
    await tester.tap(find.widgetWithText(FilledButton, '再読み込み'));
    await tester.pumpAndSettle();

    expect(find.textContaining('まだ服が登録されていません'), findsOneWidget);
  });
}
