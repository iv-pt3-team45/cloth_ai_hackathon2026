import 'dart:convert';
import 'dart:typed_data';

import '../../core/api_client.dart';
import '../../core/auth_session.dart';
import 'photo_picker.dart';
import 'wardrobe_models.dart';

/// 手持ちの服(spec 010)のデータアクセス層。
///
/// ログイン・ゲストのトークンを付けて呼ぶ(spec 038)。服はトークンの持ち主ごとに分かれる。
class WardrobeRepository {
  WardrobeRepository({ApiClient? client})
    : _client = client ?? ApiClient(auth: AuthSession.shared);

  final ApiClient _client;

  /// 取得した写真(写真名 → バイト列)。写真名は持ち主をまたいで重ならない
  final _photos = <String, Future<Uint8List>>{};

  /// 写真 1 枚を Gemini で解析する(保存はしない)。
  Future<ClothAnalysis> analyze(PickedPhoto photo) async {
    final json = await _client.post('/wardrobe/analyze', {
      'image': _image(photo),
    });
    return ClothAnalysis.fromJson(json);
  }

  /// 写真 1 枚と、確認・修正した服の属性を保存する。
  Future<List<RegisteredCloth>> register(
    PickedPhoto photo,
    List<ClothAttributes> items, {
    String summary = '',
  }) async {
    final json = await _client.post('/wardrobe/items', {
      'image': _image(photo),
      'items': items.map((item) => item.toJson()).toList(),
      'summary': summary,
    });
    return _registered(json);
  }

  /// 登録済みの服の一覧(新しい順)。
  Future<List<RegisteredCloth>> list() async =>
      _registered(await _client.get('/wardrobe/items'));

  /// 服 1 点を削除する。
  Future<void> delete(String id) async {
    await _client.delete('/wardrobe/items/${Uri.encodeComponent(id)}');
  }

  /// 保存した写真のバイト列(トークンを付けて取得する。spec 038)。
  ///
  /// 同じ写真は 1 回だけ取得する。失敗したら、次に呼ばれたときに取り直す。
  Future<Uint8List> imageBytes(String image) => _photos[image] ??= _client
      .getBytes('/wardrobe/images/${Uri.encodeComponent(image)}')
      .catchError((Object error) {
        _photos.remove(image);
        throw error;
      });

  Map<String, dynamic> _image(PickedPhoto photo) => {
    'mime_type': photo.mimeType,
    'data': base64Encode(photo.bytes),
  };

  List<RegisteredCloth> _registered(Map<String, dynamic> json) {
    final items = json['items'];
    return items is List
        ? items
              .whereType<Map<String, dynamic>>()
              .map(RegisteredCloth.fromJson)
              .toList()
        : const [];
  }
}
