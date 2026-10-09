import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tx_hackathon_gc/app/home_page.dart';
import 'package:tx_hackathon_gc/core/auth_session.dart';
import 'package:tx_hackathon_gc/core/theme.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';

import 'auth_fakes.dart';
import 'mv_lookup_fakes.dart';
import 'outfit_fakes.dart';
import 'wardrobe_fakes.dart';

/// ログイン(spec 038)まわりの画面。HomePage に偽のサーバーにつないだ AuthSession を渡す。
Future<(AuthSession, FakeWardrobeRepository)> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 4000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = makeSession(FakeAuthServer());
  final wardrobe = FakeWardrobeRepository(items: const [ownedShirt]);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: HomePage(
        mvRepository: FakeMvRepository(
          (query) async =>
              const MvLookupResult(inputType: 'url', video: confirmVideo),
        ),
        cultureRepository: FakeCultureRepository((video) async => fullReport),
        liveRepository: FakeLiveRepository(),
        venueRepository: FakeVenueRepository(),
        wardrobeRepository: wardrobe,
        photoPicker: FakePhotoPicker([]),
        outfitRepository: FakeOutfitRepository(),
        authSession: session,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (session, wardrobe);
}

Future<void> _login(WidgetTester tester, String userId, String password) async {
  await tester.enterText(find.byKey(const ValueKey('login-user-id')), userId);
  await tester.enterText(
    find.byKey(const ValueKey('login-password')),
    password,
  );
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'ログインする'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ゲストのときは ③ に案内とログインを出す(AC-14)', (tester) async {
    await _pump(tester);

    expect(find.textContaining('登録した服は 1 日で消えます'), findsOneWidget);
    expect(find.text('ゲスト'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-user-id')), findsNothing);

    // ③ の「ログイン」で入力欄が開く。「やめる」で閉じる
    await tester.tap(find.widgetWithText(FilledButton, 'ログイン'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-user-id')), findsOneWidget);
    await tester.tap(find.text('やめる'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-user-id')), findsNothing);
  });

  testWidgets('ヘッダの「ログイン」でも入力欄が開く', (tester) async {
    await _pump(tester);

    await tester.tap(find.widgetWithText(TextButton, 'ログイン'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-user-id')), findsOneWidget);
  });

  testWidgets('誤ったパスワードでは、どちらが誤りか分からない文言を出す(AC-2)', (tester) async {
    final (session, _) = await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'ログイン'));
    await tester.pumpAndSettle();

    await _login(tester, 'demo01', 'wrong');

    expect(find.text('ユーザー ID またはパスワードが違います。'), findsOneWidget);
    expect(session.isUser, isFalse);
  });

  testWidgets('ログインするとユーザー名が出て、服を読み直す。ログアウトでゲストに戻る(AC-1・AC-12)', (
    tester,
  ) async {
    final (session, wardrobe) = await _pump(tester);
    final firstLoads = wardrobe.listCalls;
    await tester.tap(find.widgetWithText(FilledButton, 'ログイン'));
    await tester.pumpAndSettle();

    await _login(tester, 'demo01', 'pass-01');

    expect(session.isUser, isTrue);
    expect(find.text('demo01'), findsOneWidget);
    expect(find.text('ログアウト'), findsOneWidget);
    expect(find.textContaining('1 日で消えます'), findsNothing);
    expect(wardrobe.listCalls, firstLoads + 1);

    await tester.tap(find.text('ログアウト'));
    await tester.pumpAndSettle();

    expect(session.isUser, isFalse);
    expect(find.text('ゲスト'), findsOneWidget);
    expect(find.textContaining('1 日で消えます'), findsOneWidget);
    expect(wardrobe.listCalls, firstLoads + 2);
  });

  testWidgets('スマホの幅でもはみ出さずに表示できる(AC-14)', (tester) async {
    await _pump(tester, size: const Size(390, 3000));
    await tester.tap(find.widgetWithText(FilledButton, 'ログイン'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('login-password')), findsOneWidget);
  });
}
