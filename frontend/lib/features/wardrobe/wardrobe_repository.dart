import 'dart:convert';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import 'photo_picker.dart';
import 'wardrobe_models.dart';

/// 手持ちの服(spec 010)のデータアクセス層。
class WardrobeRepository {
  WardrobeRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

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

  /// 保存した写真の URL。
  String imageUrl(String image) => AppConfig.endpoint(
    '/wardrobe/images/${Uri.encodeComponent(image)}',
  ).toString();

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
