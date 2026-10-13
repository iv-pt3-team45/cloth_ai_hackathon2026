import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/theme.dart';
import 'package:tx_hackathon_gc/core/widgets.dart';
import 'package:tx_hackathon_gc/features/privacy/privacy_policy.dart';
import 'package:tx_hackathon_gc/features/privacy/privacy_policy_screen.dart';

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390, 8000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: home));
  await tester.pumpAndSettle();
}

/// ポリシーの文をすべてつないだもの。
String _allText() => [
  policyIntro,
  for (final s in policySections) ...[s.title, ?s.lead, ...s.bullets, ?s.note],
].join('\n');

void main() {
  testWidgets('リンクは小さな灰色の文字で、押すとポリシーの画面が開き、← で戻る(spec 042 AC-1〜AC-3)', (
    tester,
  ) async {
    await _pump(tester, const Scaffold(body: PrivacyPolicyLink()));

    final button = tester.widget<TextButton>(find.byKey(privacyPolicyLinkKey));
    expect(button.style!.textStyle!.resolve({})!.fontSize, 12);
    expect(button.style!.foregroundColor!.resolve({}), AppColors.muted);
    expect(find.text('プライバシーポリシー'), findsOneWidget);

    await tester.tap(find.byKey(privacyPolicyLinkKey));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyScreen), findsNothing);
    expect(find.byKey(privacyPolicyLinkKey), findsOneWidget);
  });

  testWidgets('ポリシーの画面に 11 の節と、共有の注意・運営者・制定日が出る(AC-2)', (tester) async {
    await _pump(tester, const PrivacyPolicyScreen());

    expect(find.text('プライバシーポリシー'), findsOneWidget); // AppBar
    // 全文を 1 つの枠にまとめ、節は番号つきの見出しで分ける
    expect(find.byType(SectionCard), findsOneWidget);
    for (final (index, section) in policySections.indexed) {
      expect(find.text('${index + 1}. ${section.title}'), findsOneWidget);
    }
    expect(find.textContaining('すべての人で共有されます'), findsOneWidget);
    expect(find.text(policyOperator), findsOneWidget);
    expect(find.text('制定日: $policyEstablished'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('ポリシーの文は 11 節で、今の実装の要点を含む(AC-4)', () {
    final text = _allText();

    expect(policySections, hasLength(11));
    for (final point in [
      'AI のサービスに送り',
      '動画や検索のサービスに送ります',
      'クラウドのサービスを使います',
      'すべての人で共有されます',
      '利用者が削除するまで保存します',
      'しばらくのあいだ復元できる状態で残り',
      '解析だけして保存しなかった写真は、本アプリの保存先には残りません',
      'アクセス解析のツールや広告は使っていません',
      'ログインは求めません',
    ]) {
      expect(text, contains(point));
    }
    // 問い合わせ先の項目は作らない(要件の決定事項 4)
    expect(text, isNot(contains('問い合わせ')));
    // サービスの名前や日数などの具体的な値は書かない(要件の決定事項 5)
    for (final specific in [
      'Google',
      'Gemini',
      'Vertex',
      'Cloud Storage',
      'Cloud Run',
      'Firebase',
      'YouTube',
      'HTTPS',
      '日間',
      '30 日',
    ]) {
      expect(text, isNot(contains(specific)));
    }
  });
}
