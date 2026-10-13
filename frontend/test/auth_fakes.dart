import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/core/auth_session.dart';

final future = DateTime.now().add(const Duration(days: 3));
final past = DateTime.now().subtract(const Duration(hours: 1));

/// ブラウザに保存したログインの状態(SharedPreferences の初期値)。
Map<String, Object> savedLogin({
  required String kind,
  String? userId,
  required DateTime expiresAt,
}) => {
  'auth.token': 'saved-token',
  'auth.kind': kind,
  'auth.user_id': ?userId,
  'auth.expires_at': expiresAt.toIso8601String(),
};

/// ログイン・ゲスト・手持ちの服の API を真似る偽のサーバー(spec 038)。
///
/// ユーザーは demo01 / pass-01 だけ。[rejectTokens] に入れたトークンは 401 にする。
class FakeAuthServer {
  final rejectTokens = <String>{};
  int guestRequests = 0;
  int wardrobeRequests = 0;
  String? lastAuthorization;

  late final client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/auth/guest')) {
      guestRequests++;
      return _json({
        'token': 'guest-token-$guestRequests',
        'kind': 'guest',
        'user_id': null,
        'expires_at': future.toIso8601String(),
      });
    }
    if (path.endsWith('/auth/login')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['user_id'] != 'demo01' || body['password'] != 'pass-01') {
        return _json({'detail': 'ユーザー ID またはパスワードが違います。'}, status: 401);
      }
      return _json({
        'token': 'user-token',
        'kind': 'user',
        'user_id': 'demo01',
        'expires_at': future.toIso8601String(),
      });
    }
    wardrobeRequests++;
    lastAuthorization = request.headers['Authorization'];
    final token = lastAuthorization?.replaceFirst('Bearer ', '');
    if (token == null || rejectTokens.contains(token)) {
      return _json({'detail': 'ログインの期限が切れました。'}, status: 401);
    }
    return _json({'items': <Object>[], 'count': 0});
  }

  http.Response _json(Map<String, Object?> body, {int status = 200}) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// 偽のサーバーにつなぐ AuthSession。
AuthSession makeSession(FakeAuthServer server) =>
    AuthSession(client: ApiClient(client: server.client));
