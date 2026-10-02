import 'dart:convert';
import 'dart:typed_data';

import '../wardrobe/wardrobe_models.dart';

/// 提案に使う手持ちの服 1 点(spec 011)。バックエンドの SuggestedCloth と対応する。
class SuggestedCloth {
  const SuggestedCloth({required this.cloth, this.role = '', this.reason = ''});

  final RegisteredCloth cloth;

  /// コーデの中の役割(トップス・ボトムスなど)
  final String role;

  /// この服を選んだ理由
  final String reason;

  factory SuggestedCloth.fromJson(Map<String, dynamic> json) => SuggestedCloth(
    cloth: RegisteredCloth.fromJson(json),
    role: json['role'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
  );
}

/// コーデの提案(1 案)。バックエンドの OutfitSuggestion と対応する。
class OutfitSuggestion {
  const OutfitSuggestion({
    required this.items,
    this.title = '',
    this.summary = '',
    this.points = const [],
    this.excludedCount = 0,
    this.model = '',
  });

  final String title;
  final String summary;
  final List<String> points;

  /// 使う服(手持ちの服だけ)
  final List<SuggestedCloth> items;

  /// 手持ちに無かったため提案から除いた服の数
  final int excludedCount;
  final String model;

  factory OutfitSuggestion.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    final points = json['points'];
    return OutfitSuggestion(
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      points: points is List ? points.whereType<String>().toList() : const [],
      items: items is List
          ? items
                .whereType<Map<String, dynamic>>()
                .map(SuggestedCloth.fromJson)
                .toList()
          : const [],
      excludedCount: json['excluded_count'] as int? ?? 0,
      model: json['model'] as String? ?? '',
    );
  }
}

/// マネキンに提案の服を着せた画像。
class OutfitImage {
  const OutfitImage({
    required this.bytes,
    required this.mimeType,
    this.fileName = '',
    this.model = '',
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
  final String model;

  factory OutfitImage.fromJson(Map<String, dynamic> json) => OutfitImage(
    bytes: base64Decode(json['data'] as String? ?? ''),
    mimeType: json['mime_type'] as String? ?? 'image/png',
    fileName: json['file_name'] as String? ?? '',
    model: json['model'] as String? ?? '',
  );
}
