import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';

import 'auth_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('起動時(AC-11)', () {
    test('保存したユーザーのトークンが期限内なら、ログインしたまま', () async {
      SharedPreferences.setMockInitialValues(
        savedLogin(kind: 'user', userId: 'demo01', expiresAt: future),
      );
      final server = FakeAuthServer();
      final session = makeSession(server);

      await session.restore();

      expect(session.isUser, isTrue);
      expect(session.userId, 'demo01');
      expect(await session.token(), 'saved-token');
      expect(server.guestRequests, 0);
    });

    test('保存したゲストのトークンが期限内なら、同じゲストとして使う', () async {
      SharedPreferences.setMockInitialValues(
        savedLogin(kind: 'guest', expiresAt: future),
      );
      final server = FakeAuthServer();
      final session = makeSession(server);

      expect(await session.token(), 'saved-token');
      expect(session.isUser, isFalse);
      expect(server.guestRequests, 0);
    });

    test('無い・期限切れなら、ゲストのトークンをもらって保存する', () async {
      SharedPreferences.setMockInitialValues(
        savedLogin(kind: 'user', userId: 'demo01', expiresAt: past),
      );
      final server = FakeAuthServer();
      final session = makeSession(server);

      final token = await session.token();

      expect(token, 'guest-token-1');
      expect(session.isUser, isFalse);
      expect(server.guestRequests, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.token'), 'guest-token-1');
      expect(prefs.getString('auth.kind'), 'guest');
    });

    test('同時に呼ばれても、ゲストのトークンは 1 回だけもらう', () async {
      final server = FakeAuthServer();
      final session = makeSession(server);

      final tokens = await Future.wait([session.token(), session.token()]);

      expect(tokens, ['guest-token-1', 'guest-token-1']);
      expect(server.guestRequests, 1);
    });
  });

  group('ログイン・ログアウト', () {
    test('ログインするとユーザーになり、保存される(AC-1)', () async {
      final server = FakeAuthServer();
      final session = makeSession(server);
      var notified = 0;
      session.addListener(() => notified++);

      await session.login('demo01', 'pass-01');

      expect(session.isUser, isTrue);
      expect(session.userId, 'demo01');
      expect(session.ownerKey, 'user:demo01');
      expect(notified, greaterThan(0));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.user_id'), 'demo01');
      // パスワードは保存しない
      expect(prefs.getKeys().any((k) => k.contains('password')), isFalse);
    });

    test('誤りなら ApiException(401)になり、状態は変わらない(AC-2)', () async {
      final server = FakeAuthServer();
      final session = makeSession(server);

      await expectLater(
        session.login('demo01', 'wrong'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.detail, 'detail', contains('違います')),
        ),
      );
      expect(session.isUser, isFalse);
    });

    test('ログアウトするとゲストに戻り、保存も消える(AC-12)', () async {
      final server = FakeAuthServer();
      final session = makeSession(server);
      await session.login('demo01', 'pass-01');

      await session.logout();

      expect(session.isUser, isFalse);
      expect(session.ownerKey, 'guest');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.token'), isNull);
      expect(await session.token(), 'guest-token-1');
    });
  });

  group('API の 401(AC-10)', () {
    test('トークンを付けて送る', () async {
      final server = FakeAuthServer();
      final session = makeSession(server);
      final api = ApiClient(client: server.client, auth: session);

      await api.get('/wardrobe/items');

      expect(server.lastAuthorization, 'Bearer guest-token-1');
    });

    test('ゲストのトークンが無効なら、取り直して 1 回だけやり直す', () async {
      final server = FakeAuthServer()..rejectTokens.add('guest-token-1');
      final session = makeSession(server);
      final api = ApiClient(client: server.client, auth: session);

      final json = await api.get('/wardrobe/items');

      expect(json['count'], 0);
      expect(server.guestRequests, 2);
      expect(server.lastAuthorization, 'Bearer guest-token-2');
    });

    test('ユーザーのトークンが無効なら、ゲストに戻して知らせる(やり直さない)', () async {
      final server = FakeAuthServer()..rejectTokens.add('user-token');
      final session = makeSession(server);
      await session.login('demo01', 'pass-01');
      final api = ApiClient(client: server.client, auth: session);

      await expectLater(
        api.get('/wardrobe/items'),
        throwsA(isA<ApiException>()),
      );

      expect(session.isUser, isFalse);
      expect(session.notice, contains('期限が切れました'));
      expect(server.wardrobeRequests, 1);
    });

    test('トークンを付けないクライアントはヘッダを送らない', () async {
      String? authorization = 'unset';
      final client = MockClient((request) async {
        authorization = request.headers['Authorization'];
        return http.Response(jsonEncode({'ok': true}), 200);
      });

      await ApiClient(client: client).get('/youtube/lookup');

      expect(authorization, isNull);
    });
  });
}
