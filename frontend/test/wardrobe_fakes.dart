import 'dart:convert';

import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/features/wardrobe/photo_picker.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_models.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_repository.dart';

/// 1x1 の PNG(Image.memory で表示できる本物の画像)。
final pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

PickedPhoto photo(String name, {String? mimeType = 'image/png'}) =>
    PickedPhoto(name: name, bytes: pngBytes, mimeType: mimeType);

const shirt = ClothAttributes(
  category: 'Tシャツ',
  material: '綿',
  shape: '半袖',
  colors: ['白'],
  style: 'カジュアル',
  seasons: ['春', '夏'],
  warmth: '薄手',
  occasions: ['普段着'],
);

const jeans = ClothAttributes(
  category: 'ジーンズ',
  material: 'デニム',
  shape: 'ストレート',
  colors: ['青'],
  warmth: '普通',
);

/// 保存の呼び出し 1 回ぶん。
typedef RegisterCall = ({
  PickedPhoto photo,
  List<ClothAttributes> items,
  String summary,
});

/// バックエンドを呼ばない手持ちの服のリポジトリ。呼び出しを記録し、保存した服を一覧に返す。
class FakeWardrobeRepository implements WardrobeRepository {
  FakeWardrobeRepository({
    List<RegisteredCloth> items = const [],
    this.analyzeResponder,
    this.listError,
    this.registerErrors = const {},
  }) : items = List.of(items);

  final List<RegisteredCloth> items;
  Future<ClothAnalysis> Function(PickedPhoto photo)? analyzeResponder;
  ApiException? listError;

  /// 写真の名前 → 保存で投げる例外
  Map<String, ApiException> registerErrors;

  final analyzed = <String>[];
  final registered = <RegisterCall>[];
  final deleted = <String>[];
  int _next = 0;

  @override
  Future<ClothAnalysis> analyze(PickedPhoto photo) {
    analyzed.add(photo.name);
    final respond = analyzeResponder;
    if (respond != null) return respond(photo);
    return Future.value(
      const ClothAnalysis(items: [shirt], summary: '白い T シャツ'),
    );
  }

  @override
  Future<List<RegisteredCloth>> register(
    PickedPhoto photo,
    List<ClothAttributes> items, {
    String summary = '',
  }) async {
    final error = registerErrors[photo.name];
    if (error != null) throw error;
    registered.add((photo: photo, items: items, summary: summary));
    final saved = [
      for (final attributes in items)
        RegisteredCloth(
          id: 'id${_next++}',
          image: '${photo.name}.png',
          attributes: attributes,
        ),
    ];
    this.items.insertAll(0, saved);
    return saved;
  }

  @override
  Future<List<RegisteredCloth>> list() async {
    final error = listError;
    if (error != null) throw error;
    return List.of(items);
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    items.removeWhere((item) => item.id == id);
  }

  // 空にすると一覧はプレースホルダを出す(テストでネットワークから画像を読まないため)
  @override
  String imageUrl(String image) => '';
}

/// 決めておいた写真を返す PhotoPicker。
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker(this.photos);

  final List<PickedPhoto> photos;
  int? requestedLimit;

  @override
  Future<List<PickedPhoto>> pick({required int limit}) async {
    requestedLimit = limit;
    return photos;
  }
}
