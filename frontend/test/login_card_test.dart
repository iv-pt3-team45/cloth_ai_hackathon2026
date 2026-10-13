import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tx_hackathon_gc/app/home_page.dart';
import 'package:tx_hackathon_gc/core/auth_session.dart';
import 'package:tx_hackathon_gc/core/theme.dart';
import 'package:tx_hackathon_gc/features/auth/login_page.dart';
import 'package:tx_hackathon_gc/features/auth/register_page.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_panel.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';

import 'auth_fakes.dart';
import 'mv_lookup_fakes.dart';
import 'outfit_fakes.dart';
import 'wardrobe_fakes.dart';

/// ログイン画面・ユーザー登録画面(spec 040)とログイン(spec 038)まわりの画面。
/// HomePage に偽のサーバーにつないだ AuthSession を渡す。
///
/// 配色の背景の動き(spec 039)は止まらないので、端末の「動きを減らす」を有効にする。
Future<(AuthSession, FakeWardrobeRepository, FakeAuthServer)> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 4000),
  CultureReport culture = fullReport,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final server = FakeAuthServer();
  final session = makeSession(server);
  final wardrobe = FakeWardrobeRepository(items: const [ownedShirt]);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: HomePage(
        mvRepository: FakeMvRepository(
          (query) async =>
              const MvLookupResult(inputType: 'url', video: confirmVideo),
        ),
        cultureRepository: FakeCultureRepository((video) async => culture),
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
  return (session, wardrobe, server);
}

/// ③ の「ログイン」でログイン画面を開く。
Future<void> _openFromCard(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'ログイン'));
  await tester.pumpAndSettle();
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

Future<void> _openRegister(WidgetTester tester) async {
  await _openFromCard(tester);
  await tester.tap(find.text('新規登録はこちら'));
  await tester.pumpAndSettle();
}

Future<void> _fillRegister(
  WidgetTester tester, {
  required String userId,
  required String password,
  required String confirm,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('register-user-id')),
    userId,
  );
  await tester.enterText(
    find.byKey(const ValueKey('register-password')),
    password,
  );
  await tester.enterText(
    find.byKey(const ValueKey('register-confirm')),
    confirm,
  );
  await tester.tap(find.widgetWithText(FilledButton, '登録する'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('③ のカード', () {
    testWidgets('ゲストのときは説明と「ログイン」だけを出し、入力欄は出さない(040 AC-11)', (tester) async {
      await _pump(tester);

      expect(find.textContaining('登録した服は 1 日で消えます'), findsOneWidget);
      expect(find.text('ゲスト'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'ログイン'), findsOneWidget);
      expect(find.byKey(const ValueKey('login-user-id')), findsNothing);
    });
  });

  group('ログイン画面', () {
    testWidgets('③ の「ログイン」でログイン画面が開き、入力欄とボタンが出る(AC-1)', (tester) async {
      await _pump(tester);
      await _openFromCard(tester);

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byKey(const ValueKey('login-user-id')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-password')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'ログインする'), findsOneWidget);
      expect(find.text('ゲストのまま戻る'), findsOneWidget);
      expect(find.text('新規登録はこちら'), findsOneWidget);
    });

    testWidgets('ヘッダの「ログイン」でもログイン画面が開く(AC-1)', (tester) async {
      await _pump(tester);

      await tester.tap(find.widgetWithText(TextButton, 'ログイン'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('ログインすると画面が閉じ、ユーザー名が出て服を読み直す。ログアウトでゲストに戻る(AC-2)', (
      tester,
    ) async {
      final (session, wardrobe, _) = await _pump(tester);
      final firstLoads = wardrobe.listCalls;
      await _openFromCard(tester);

      await _login(tester, 'demo01', 'pass-01');

      expect(find.byType(LoginPage), findsNothing);
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

    testWidgets('誤ったパスワードでは画面を閉じず、どちらが誤りか分からない文言を出す(AC-3)', (tester) async {
      final (session, _, _) = await _pump(tester);
      await _openFromCard(tester);

      await _login(tester, 'demo01', 'wrong');

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('ユーザー ID またはパスワードが違います。'), findsOneWidget);
      expect(session.isUser, isFalse);
    });

    testWidgets('ID かパスワードが空なら「ログインする」は押せない(AC-4)', (tester) async {
      await _pump(tester);
      await _openFromCard(tester);
      FilledButton button() =>
          tester.widget(find.widgetWithText(FilledButton, 'ログインする'));

      expect(button().onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('login-user-id')),
        'demo01',
      );
      await tester.pump();
      expect(button().onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'pass-01',
      );
      await tester.pump();
      expect(button().onPressed, isNotNull);
    });

    testWidgets('パスワードの表示を切り替えられ、エンターでログインできる(AC-5)', (tester) async {
      final (session, _, _) = await _pump(tester);
      await _openFromCard(tester);
      bool obscured() => tester
          .widget<TextField>(find.byKey(const ValueKey('login-password')))
          .obscureText;

      expect(obscured(), isTrue);
      await tester.tap(find.byTooltip('パスワードを表示'));
      await tester.pump();
      expect(obscured(), isFalse);
      await tester.tap(find.byTooltip('パスワードを隠す'));
      await tester.pump();
      expect(obscured(), isTrue);

      await tester.enterText(
        find.byKey(const ValueKey('login-user-id')),
        'demo01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'pass-01',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(session.isUser, isTrue);
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('ログイン画面から戻っても、ログインしても、① の入力と取得したカルチャー情報は残る(AC-6)', (
      tester,
    ) async {
      await _pump(tester);
      await tester.enterText(
        find.byKey(mvQueryFieldKey),
        'https://youtu.be/abc',
      );
      await tester.tap(find.byKey(mvSearchButtonKey));
      await tester.pumpAndSettle();
      String query() => tester
          .widget<TextField>(find.byKey(mvQueryFieldKey))
          .controller!
          .text;
      expect(find.text('くわしく見る'), findsOneWidget);

      // 「ゲストのまま戻る」
      await _openFromCard(tester);
      await tester.tap(find.text('ゲストのまま戻る'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing);
      expect(query(), 'https://youtu.be/abc');
      expect(find.text('くわしく見る'), findsOneWidget);

      // 上部の戻るボタン
      await _openFromCard(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing);
      expect(query(), 'https://youtu.be/abc');

      // ログインして戻る
      await _openFromCard(tester);
      await _login(tester, 'demo01', 'pass-01');
      expect(query(), 'https://youtu.be/abc');
      expect(find.text('くわしく見る'), findsOneWidget);
    });
  });

  group('ユーザー登録画面', () {
    testWidgets('「新規登録はこちら」で開き、入力欄・ボタン・注記が出る(AC-7)', (tester) async {
      await _pump(tester);
      await _openRegister(tester);

      expect(find.byType(RegisterPage), findsOneWidget);
      expect(find.byKey(const ValueKey('register-user-id')), findsOneWidget);
      expect(find.byKey(const ValueKey('register-password')), findsOneWidget);
      expect(find.byKey(const ValueKey('register-confirm')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '登録する'), findsOneWidget);
      expect(find.text('ログイン画面へ戻る'), findsOneWidget);
      expect(find.text(registerClosedNote), findsOneWidget);
      expect(find.text(registerClosedMessage), findsNothing);
    });

    testWidgets('規則に合わない入力では欄ごとに理由を出し、案内は出さない(AC-8)', (tester) async {
      await _pump(tester);
      await _openRegister(tester);

      await _fillRegister(
        tester,
        userId: 'Demo',
        password: 'short',
        confirm: 'other',
      );

      expect(
        find.text('ユーザー ID は英小文字・数字・_・- の 3〜32 文字にしてください。'),
        findsOneWidget,
      );
      expect(find.text('パスワードは 8 文字以上にしてください。'), findsOneWidget);
      expect(find.text('確認のパスワードが一致しません。'), findsOneWidget);
      expect(find.text(registerClosedMessage), findsNothing);

      // 直すと、その場で理由が消える
      await tester.enterText(
        find.byKey(const ValueKey('register-user-id')),
        'demo06',
      );
      await tester.pumpAndSettle();
      expect(find.text('ユーザー ID は英小文字・数字・_・- の 3〜32 文字にしてください。'), findsNothing);
    });

    testWidgets('正しい入力で「登録する」を押すと案内を出し、サーバーには送らない(AC-9)', (tester) async {
      final (session, _, server) = await _pump(tester);
      await _openRegister(tester);
      final requests = (server.guestRequests, server.wardrobeRequests);

      await _fillRegister(
        tester,
        userId: 'demo06',
        password: 'password-06',
        confirm: 'password-06',
      );

      expect(find.text(registerClosedMessage), findsOneWidget);
      expect((server.guestRequests, server.wardrobeRequests), requests);
      expect(session.isUser, isFalse);
    });

    testWidgets('「ログイン画面へ戻る」でログイン画面に戻る(AC-10)', (tester) async {
      await _pump(tester);
      await _openRegister(tester);

      await tester.tap(find.text('ログイン画面へ戻る'));
      await tester.pumpAndSettle();

      expect(find.byType(RegisterPage), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('共通(AC-12)', () {
    testWidgets('幅 390px でも、ログイン画面・登録画面・案内がはみ出さない', (tester) async {
      await _pump(tester, size: const Size(390, 844));

      // スマホの高さでは ③ が画面の外なので、ヘッダの「ログイン」から開く
      await tester.tap(find.widgetWithText(TextButton, 'ログイン'));
      await tester.pumpAndSettle();
      await _login(tester, 'demo01', 'wrong');
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('新規登録はこちら'));
      await tester.pumpAndSettle();
      await _fillRegister(
        tester,
        userId: 'x',
        password: 'short',
        confirm: 'other',
      );
      expect(tester.takeException(), isNull);
      await _fillRegister(
        tester,
        userId: 'demo06',
        password: 'password-06',
        confirm: 'password-06',
      );
      expect(tester.takeException(), isNull);
      expect(find.text(registerClosedMessage), findsOneWidget);
    });

    testWidgets('MV に合わせた暗い配色の最中に開くと、その配色を引き継ぐ(spec 039)', (tester) async {
      await _pump(
        tester,
        culture: const CultureReport(
          artist: 'YOASOBI',
          identified: true,
          fashion: FashionInfo(styles: ['ロック'], colors: ['赤']),
        ),
      );
      await tester.enterText(
        find.byKey(mvQueryFieldKey),
        'https://youtu.be/abc',
      );
      await tester.tap(find.byKey(mvSearchButtonKey));
      await tester.pumpAndSettle();
      final home = AppPalette.of(tester.element(find.text('MV を選ぶ')));
      expect(home.dark, isTrue);

      await _openFromCard(tester);
      expect(AppPalette.of(tester.element(find.text('ログインする'))), home);

      await tester.tap(find.text('新規登録はこちら'));
      await tester.pumpAndSettle();
      expect(AppPalette.of(tester.element(find.text('登録する'))), home);
    });
  });
}
