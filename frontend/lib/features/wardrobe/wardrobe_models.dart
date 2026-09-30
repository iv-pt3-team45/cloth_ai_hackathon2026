/// 季節・暖かさ・使う場面の選択肢(バックエンドの app/schemas/wardrobe.py と揃える)。
const seasonChoices = ['春', '夏', '秋', '冬'];
const warmthChoices = ['薄手', '普通', '厚手'];
const occasionChoices = ['普段着', 'きれいめ', 'フォーマル', 'スポーツ・アウトドア', 'ライブ・フェス'];

/// 1 回にまとめて登録できる写真の枚数。
const maxPhotosPerBatch = 10;

/// 使う場面の画面上の名前(値と違うものだけ説明を付ける)。
String occasionLabel(String value) => value == 'きれいめ' ? 'きれいめ(食事・オフィス)' : value;

const _unset = Object();

/// 服 1 点の属性。バックエンドの ClothAttributes と対応する。
class ClothAttributes {
  const ClothAttributes({
    this.category = '',
    this.material = '',
    this.shape = '',
    this.colors = const [],
    this.pattern = '',
    this.style = '',
    this.notes = '',
    this.seasons = const [],
    this.warmth,
    this.occasions = const [],
  });

  /// 種類(Tシャツ、パンツなど)
  final String category;
  final String material;

  /// 形・シルエット
  final String shape;

  /// 色。目立つ順
  final List<String> colors;
  final String pattern;

  /// 系統(自由な語)
  final String style;

  /// プリントの文言や装飾などの特徴
  final String notes;
  final List<String> seasons;

  /// 暖かさ。分からなければ null
  final String? warmth;
  final List<String> occasions;

  ClothAttributes copyWith({
    String? category,
    String? material,
    String? shape,
    List<String>? colors,
    String? pattern,
    String? style,
    String? notes,
    List<String>? seasons,
    Object? warmth = _unset,
    List<String>? occasions,
  }) => ClothAttributes(
    category: category ?? this.category,
    material: material ?? this.material,
    shape: shape ?? this.shape,
    colors: colors ?? this.colors,
    pattern: pattern ?? this.pattern,
    style: style ?? this.style,
    notes: notes ?? this.notes,
    seasons: seasons ?? this.seasons,
    warmth: identical(warmth, _unset) ? this.warmth : warmth as String?,
    occasions: occasions ?? this.occasions,
  );

  factory ClothAttributes.fromJson(Map<String, dynamic> json) =>
      ClothAttributes(
        category: json['category'] as String? ?? '',
        material: json['material'] as String? ?? '',
        shape: json['shape'] as String? ?? '',
        colors: _strings(json['colors']),
        pattern: json['pattern'] as String? ?? '',
        style: json['style'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        seasons: _strings(json['seasons']),
        warmth: json['warmth'] as String?,
        occasions: _strings(json['occasions']),
      );

  Map<String, dynamic> toJson() => {
    'category': category,
    'material': material,
    'shape': shape,
    'colors': colors,
    'pattern': pattern,
    'style': style,
    'notes': notes,
    'seasons': seasons,
    'warmth': warmth,
    'occasions': occasions,
  };
}

/// 写真 1 枚の解析結果(保存前)。
class ClothAnalysis {
  const ClothAnalysis({
    this.items = const [],
    this.summary = '',
    this.model = '',
  });

  /// 写っている服。服が写っていなければ空
  final List<ClothAttributes> items;
  final String summary;
  final String model;

  factory ClothAnalysis.fromJson(Map<String, dynamic> json) => ClothAnalysis(
    items: _maps(json['items']).map(ClothAttributes.fromJson).toList(),
    summary: json['summary'] as String? ?? '',
    model: json['model'] as String? ?? '',
  );
}

/// 登録済みの服 1 点。
class RegisteredCloth {
  const RegisteredCloth({
    required this.id,
    required this.image,
    required this.attributes,
    this.registeredAt,
  });

  /// 服の ID(削除に使う)
  final String id;

  /// 写真のファイル名
  final String image;
  final ClothAttributes attributes;
  final DateTime? registeredAt;

  factory RegisteredCloth.fromJson(Map<String, dynamic> json) {
    final registeredAt = json['registered_at'];
    return RegisteredCloth(
      id: json['id'] as String,
      image: json['image'] as String? ?? '',
      attributes: ClothAttributes.fromJson(json),
      registeredAt: registeredAt is String
          ? DateTime.tryParse(registeredAt)
          : null,
    );
  }
}

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

List<Map<String, dynamic>> _maps(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];
