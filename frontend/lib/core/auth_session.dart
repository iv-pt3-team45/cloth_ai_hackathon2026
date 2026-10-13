import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// 持ち主の種類(spec 038)。ログインしたユーザーか、ゲスト。
enum AuthKind { user, guest }

/// ログインの状態(spec 038)。
///
/// ログインしたユーザーもゲストも、サーバーが発行したトークンを持ち、手持ちの服・コーデ提案の
/// API に付けて送る([ApiClient])。トークンはブラウザに保存し、再読み込み・開き直しても使う。
/// ゲストのトークンは、必要になったとき([token])に自動でもらう。
class AuthSession extends ChangeNotifier {
  AuthSession({
    ApiClient? client,
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? clock,
  }) : _client = client ?? ApiClient(),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _clock = clock ?? DateTime.now;

  /// アプリで 1 つの状態。テストでは別のインスタンスを渡す。
  static final AuthSession shared = AuthSession();

  static const _tokenKey = 'auth.token';
  static const _kindKey = 'auth.kind';
  static const _userIdKey = 'auth.user_id';
  static const _expiresAtKey = 'auth.expires_at';

  /// 期限の少し前に切れたものとして扱う(送っている途中で切れないように)
  static const _margin = Duration(minutes: 1);

  final ApiClient _client;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _clock;

  String? _token;
  AuthKind? _kind;
  String? _userId;
  DateTime? _expiresAt;
  Future<void>? _restoring;
  Future<String>? _startingGuest;
  String? _notice;

  /// ログイン中か(ゲストなら false)。
  bool get isUser => _kind == AuthKind.user && _valid;

  /// ログイン中のユーザー ID(ゲストなら null)。
  String? get userId => isUser ? _userId : null;

  /// 手持ちの服の持ち主が変わったかを見分ける値(ゲストはまとめて 1 つ)。
  String get ownerKey => isUser ? 'user:$_userId' : 'guest';

  /// 利用者に伝えること(ログインの期限切れなど)。[clearNotice] で消す。
  String? get notice => _notice;

  bool get _valid {
    final expiresAt = _expiresAt;
    return _token != null &&
        expiresAt != null &&
        _clock().isBefore(expiresAt.subtract(_margin));
  }

  /// 保存してあるトークンを読み込む(何度呼んでも 1 回だけ読む)。期限切れなら捨てる。
  Future<void> restore() => _restoring ??= _restore();

  Future<void> _restore() async {
    try {
      final prefs = await _preferences();
      final kind = prefs.getString(_kindKey);
      _token = prefs.getString(_tokenKey);
      _kind = AuthKind.values.where((k) => k.name == kind).firstOrNull;
      _userId = prefs.getString(_userIdKey);
      _expiresAt = DateTime.tryParse(prefs.getString(_expiresAtKey) ?? '');
    } on Exception {
      // 保存領域を使えない環境(テストなど)では、保存せずに使う
    }
    if (!_valid) _clear();
    notifyListeners();
  }

  /// API に付けるトークン。無い・期限切れなら、ゲストのトークンをもらう。
  Future<String> token() async {
    await restore();
    if (_valid) return _token!;
    return _startGuest();
  }

  /// ID とパスワードでログインする。失敗したら [ApiException](401 など)。
  Future<void> login(String userId, String password) async {
    final json = await _client.post('/auth/login', {
      'user_id': userId,
      'password': password,
    });
    _notice = null;
    await _save(json);
  }

  /// ログアウトする(ゲストに戻る)。サーバーには何も送らない。
  Future<void> logout() async {
    _clear();
    await _persist();
    notifyListeners();
  }

  /// API が 401 を返したときの扱い。送ったトークンを渡す。もう一度送ってよければ true。
  ///
  /// - ユーザー: ログインの期限切れとしてゲストに戻す(画面の表示が変わるため、やり直さない)。
  /// - ゲスト: 新しいゲストのトークンをもらい、やり直す。
  Future<bool> onUnauthorized(String sentToken) async {
    if (sentToken != _token) return true; // 別の呼び出しで既に入れ替わった
    if (_kind == AuthKind.user) {
      _notice = 'ログインの期限が切れました。もう一度ログインしてください。';
      await logout();
      return false;
    }
    _clear();
    await _startGuest();
    return true;
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  Future<String> _startGuest() => _startingGuest ??= () async {
    try {
      await _save(await _client.post('/auth/guest', const {}));
      return _token!;
    } finally {
      _startingGuest = null;
    }
  }();

  Future<void> _save(Map<String, dynamic> json) async {
    _token = json['token'] as String?;
    _kind = json['kind'] == 'user' ? AuthKind.user : AuthKind.guest;
    _userId = json['user_id'] as String?;
    _expiresAt = DateTime.tryParse(json['expires_at'] as String? ?? '');
    if (_token == null || _expiresAt == null) {
      _clear();
      throw ApiException('ログインの応答を読み取れませんでした');
    }
    await _persist();
    notifyListeners();
  }

  void _clear() {
    _token = null;
    _kind = null;
    _userId = null;
    _expiresAt = null;
  }

  Future<void> _persist() async {
    try {
      final prefs = await _preferences();
      final token = _token;
      if (token == null) {
        await Future.wait([
          for (final key in [_tokenKey, _kindKey, _userIdKey, _expiresAtKey])
            prefs.remove(key),
        ]);
        return;
      }
      await Future.wait([
        prefs.setString(_tokenKey, token),
        prefs.setString(_kindKey, _kind!.name),
        if (_userId != null)
          prefs.setString(_userIdKey, _userId!)
        else
          prefs.remove(_userIdKey),
        prefs.setString(_expiresAtKey, _expiresAt!.toIso8601String()),
      ]);
    } on Exception {
      // 保存できなくても、このページを開いている間は使える
    }
  }
}
