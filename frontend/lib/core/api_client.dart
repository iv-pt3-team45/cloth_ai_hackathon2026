import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

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
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> get(String path) async {
    final response = await _client.get(AppConfig.endpoint(path));
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post(
      AppConfig.endpoint(path),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        utf8.decode(response.bodyBytes),
        statusCode: response.statusCode,
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  void close() => _client.close();
}
