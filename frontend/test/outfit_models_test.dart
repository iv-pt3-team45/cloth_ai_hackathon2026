import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_models.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_models.dart';

import 'mv_lookup_fakes.dart';

void main() {
  test('OutfitSuggestion.fromJson はバックエンドの OutfitSuggestion を読める', () {
    final suggestion = OutfitSuggestion.fromJson({
      'title': '晴れの日のコーデ',
      'summary': '説明',
      'points': ['薄手で'],
      'items': [
        {
          'id': 'shirt',
          'image': 'a.png',
          'category': 'Tシャツ',
          'colors': ['白'],
          'seasons': ['夏'],
          'warmth': '薄手',
          'occasions': ['ライブ・フェス'],
          'role': 'トップス',
          'reason': '白で合わせやすい',
        },
      ],
      'excluded_count': 1,
      'model': 'gemini',
    });

    final item = suggestion.items.single;
    expect(suggestion.title, '晴れの日のコーデ');
    expect(suggestion.points, ['薄手で']);
    expect(suggestion.excludedCount, 1);
    expect(item.cloth.id, 'shirt');
    expect(item.cloth.attributes.warmth, '薄手');
    expect((item.role, item.reason), ('トップス', '白で合わせやすい'));
  });

  test('OutfitImage.fromJson は base64 を画像のバイト列に戻す', () {
    final image = OutfitImage.fromJson({
      'mime_type': 'image/png',
      'data': base64Encode([1, 2, 3]),
      'file_name': 'outfit-1.png',
    });

    expect(image.bytes, [1, 2, 3]);
    expect(image.fileName, 'outfit-1.png');
  });

  test('CultureReport.toJson はバックエンドの CultureResponse の形で送り返せる', () {
    final json = fullReport.toJson();

    expect(json['artist'], 'YOASOBI');
    expect((json['fashion'] as Map)['styles'], ['ストリート']);
    expect(
      ((json['mv_outfit'] as Map)['looks'] as List).single['label'],
      'メインの衣装',
    );
    final restored = CultureReport.fromJson(jsonDecode(jsonEncode(json)));
    expect(restored.background.genres, ['J-POP']);
    expect(restored.mvOutfit.looks.single.items.single.category, 'ワンピース');
  });

  test('LiveCandidate.toJson は日付を YYYY-MM-DD で送る', () {
    final candidate = liveResult().candidates.first;

    final json = candidate.toJson();

    expect(json['date'], '2023-06-04');
    expect((json['weather'] as Map)['kind'], 'actual');
    expect(LiveCandidate.fromJson(json).weather.highC, 27);
  });
}
