import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'auth_session.dart';

/// API 呼び出しが失敗したときに投げる例外。
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// レスポンスボディ(FastAPI の `{"detail": ...}`)から利用者向けの文言を取り出す。
  ///
  /// 取り出せなければ本文([message])をそのまま返す。
  String get detail {
    final Object? body;
    try {
      body = jsonDecode(message);
    } on FormatException {
      return message;
    }
    final detail = body is Map<String, dynamic> ? body['detail'] : null;
    if (detail is String) return detail;
    if (detail is List) {
      // 422(入力検証エラー)は項目ごとの一覧で返る
      return detail.map((e) => e is Map ? e['msg'] ?? e : e).join('\n');
    }
    return message;
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// バックエンドとの HTTP 通信を担う薄いクライアント。
///
/// [auth] を渡すと、ログイン・ゲストのトークンを `Authorization` に付けて送る
/// (手持ちの服・コーデ提案。spec 038)。401 が返ったら [AuthSession.onUnauthorized] に任せ、
/// ゲストのトークンを取り直したときは 1 回だけやり直す。
class ApiClient {
  ApiClient({http.Client? client, AuthSession? auth})
    : _client = client ?? http.Client(),
      _auth = auth;

  final http.Client _client;
  final AuthSession? _auth;

  Future<Map<String, dynamic>> get(String path) async => _decode(
    await _send((headers) => _client.get(_url(path), headers: headers)),
  );

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async => _decode(
    await _send(
      (headers) => _client.post(
        _url(path),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    ),
  );

  Future<Map<String, dynamic>> delete(String path) async => _decode(
    await _send((headers) => _client.delete(_url(path), headers: headers)),
  );

  /// 本文をバイト列のまま受け取る(写真など)。
  Future<Uint8List> getBytes(String path) async {
    final response = await _send(
      (headers) => _client.get(_url(path), headers: headers),
    );
    _check(response);
    return response.bodyBytes;
  }

  Uri _url(String path) => AppConfig.endpoint(path);

  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    final auth = _auth;
    if (auth == null) return request(const {});
    for (var attempt = 0; ; attempt++) {
      final token = await auth.token();
      final response = await request({'Authorization': 'Bearer $token'});
      if (response.statusCode != 401 || attempt > 0) return response;
      if (!await auth.onUnauthorized(token)) return response;
    }
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        utf8.decode(response.bodyBytes),
        statusCode: response.statusCode,
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    _check(response);
    // 204(削除など)は本文が空
    if (response.bodyBytes.isEmpty) return const {};
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  void close() => _client.close();
}
