import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/features/wardrobe/photo_picker.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_models.dart';

void main() {
  test('RegisteredCloth.fromJson はバックエンドの RegisteredCloth を読める', () {
    final cloth = RegisteredCloth.fromJson({
      'id': 'abc123',
      'image': 'cloth-1.jpg',
      'registered_at': '2026-09-30T10:00:00+09:00',
      'category': 'Tシャツ',
      'material': '綿',
      'shape': '半袖',
      'colors': ['白'],
      'pattern': '無地',
      'style': 'カジュアル',
      'notes': '',
      'seasons': ['春', '夏'],
      'warmth': null,
      'occasions': ['ライブ・フェス'],
    });

    expect(cloth.id, 'abc123');
    expect(cloth.registeredAt, isNotNull);
    expect(cloth.attributes.category, 'Tシャツ');
    expect(cloth.attributes.seasons, ['春', '夏']);
    expect(cloth.attributes.warmth, isNull);
    expect(cloth.attributes.occasions, ['ライブ・フェス']);
  });

  test('ClothAttributes.toJson はバックエンドの ClothAttributes の形になる', () {
    const attributes = ClothAttributes(
      category: 'コート',
      colors: ['黒'],
      seasons: ['冬'],
      warmth: '厚手',
      occasions: ['きれいめ'],
    );

    final json = attributes.toJson();

    expect(json['category'], 'コート');
    expect(json['warmth'], '厚手');
    expect(json['occasions'], ['きれいめ']);
    expect(ClothAttributes.fromJson(json).seasons, ['冬']);
  });

  test('copyWith は暖かさを null に戻せる', () {
    const attributes = ClothAttributes(category: 'コート', warmth: '厚手');

    expect(attributes.copyWith(category: 'ジャケット').warmth, '厚手');
    expect(attributes.copyWith(warmth: null).warmth, isNull);
  });

  test('ClothAnalysis.fromJson', () {
    final analysis = ClothAnalysis.fromJson({
      'items': [
        {'category': 'Tシャツ'},
        {'category': 'ジーンズ'},
      ],
      'summary': '2 点',
      'model': 'gemini',
    });

    expect(analysis.items.map((i) => i.category), ['Tシャツ', 'ジーンズ']);
    expect(analysis.summary, '2 点');
  });

  test('occasionLabel は「きれいめ」に説明を付ける', () {
    expect(occasionLabel('きれいめ'), 'きれいめ(食事・オフィス)');
    expect(occasionLabel('ライブ・フェス'), 'ライブ・フェス');
  });

  group('detectMimeType', () {
    test('報告された形式を優先し、対応外なら null', () {
      expect(detectMimeType('a.jpg', 'image/png'), 'image/png');
      expect(detectMimeType('a.jpg', 'image/heic'), isNull);
    });

    test('報告が無ければ拡張子で判定する', () {
      expect(detectMimeType('A.JPEG', null), 'image/jpeg');
      expect(detectMimeType('a.webp', ''), 'image/webp');
      expect(detectMimeType('a.heic', null), isNull);
    });
  });
}
