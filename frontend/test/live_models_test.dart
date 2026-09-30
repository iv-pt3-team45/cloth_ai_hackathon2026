import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_models.dart';

void main() {
  test('LiveSearchResult.fromJson はバックエンドの LiveSearchResponse を読める', () {
    final result = LiveSearchResult.fromJson({
      'artist': 'YOASOBI',
      'found': true,
      'message': '',
      'candidates': [
        {
          'index': 1,
          'artist': null,
          'live_name': '公演A',
          'venue': 'さいたまスーパーアリーナ',
          'location': '埼玉県さいたま市',
          'date': '2023-06-04',
          'weather': {
            'kind': 'actual',
            'summary': '晴れ',
            'high_c': 27,
            'low_c': 18.5,
            'precipitation_chance': null,
          },
          'source_indices': [1, 2],
        },
      ],
      'sources': [
        {'index': 1, 'title': '記事', 'url': 'https://example.com', 'domain': ''},
      ],
      'search_suggestions_html': '<div></div>',
      'web_search_queries': ['YOASOBI ライブ'],
      'model': 'gemini-2.5-flash',
    });

    final candidate = result.candidates.single;
    expect(result.found, isTrue);
    expect(result.artist, 'YOASOBI');
    expect(candidate.artist, isNull);
    expect(candidate.date, DateTime(2023, 6, 4));
    expect(candidate.weather.highC, 27.0);
    expect(candidate.weather.lowC, 18.5);
    expect(candidate.sourceIndices, [1, 2]);
    expect(result.sources.single.url, 'https://example.com');
  });

  test('日付と天気が欠けていても読める', () {
    final candidate = LiveCandidate.fromJson({
      'index': 2,
      'live_name': '公演B',
      'date': null,
      'weather': {'kind': 'unknown'},
    });

    expect(candidate.date, isNull);
    expect(candidate.weather.kind, 'unknown');
  });

  group('LiveWeather.description', () {
    test('実績は値と「実績」を出す(整数の気温は小数点を付けない)', () {
      const weather = LiveWeather(
        kind: 'actual',
        summary: '晴れ',
        highC: 27,
        lowC: 18.5,
        precipitationChance: 10,
      );
      expect(weather.description, '晴れ / 最高 27℃ / 最低 18.5℃ / 降水確率 10%(実績)');
    });

    test('予報は「予報」を出す', () {
      const weather = LiveWeather(kind: 'forecast', summary: '雨');
      expect(weather.description, '雨(予報)');
    });

    test('予報がまだ無い / 不明', () {
      expect(const LiveWeather(kind: 'not_yet').description, '予報はまだありません');
      expect(const LiveWeather(kind: 'unknown').description, '不明');
      expect(const LiveWeather(kind: 'actual').description, '不明(実績)');
    });
  });
}
