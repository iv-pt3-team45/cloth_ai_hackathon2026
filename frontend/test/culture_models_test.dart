import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';

void main() {
  test('CultureReport.fromJson はバックエンドの CultureResponse を読める', () {
    final report = CultureReport.fromJson({
      'artist': 'YOASOBI',
      'identified': true,
      'message': '',
      'fashion': {
        'styles': ['ストリート'],
        'colors': ['黒', '白'],
        'items': ['ベレー帽'],
        'worldview': '世界観',
        'source_indices': [1, 2],
      },
      'background': {
        'summary': '概要',
        'history': ['2019年 結成'],
        'genres': ['J-POP'],
        'representative_songs': ['夜に駆ける'],
        'musical_traits': '',
        'source_indices': [1],
      },
      'mv_outfit': {
        'status': 'ok',
        'message': '',
        'looks': [
          {
            'label': 'メインの衣装',
            'items': [
              {
                'category': 'ワンピース',
                'material': '不明',
                'shape': 'ミニ丈',
                'colors': ['白'],
                'pattern': '無地',
                'style': 'ガーリー',
                'notes': '',
              },
            ],
          },
        ],
      },
      'sources': [
        {
          'index': 1,
          'title': '記事A',
          'url': 'https://example.com/a',
          'domain': 'example.com',
        },
      ],
      'search_suggestions_html': '<div></div>',
      'web_search_queries': ['YOASOBI ファッション'],
      'model': 'gemini-2.5-flash',
    });

    expect(report.identified, isTrue);
    expect(report.fashion.colors, ['黒', '白']);
    expect(report.fashion.sourceIndices, [1, 2]);
    expect(report.background.history, ['2019年 結成']);
    expect(report.mvOutfit.isOk, isTrue);
    expect(report.mvOutfit.looks.single.items.single.category, 'ワンピース');
    expect(report.sources.single.domain, 'example.com');
    expect(report.webSearchQueries, ['YOASOBI ファッション']);
  });

  test('項目が欠けていても既定値で読める', () {
    final report = CultureReport.fromJson({
      'artist': '',
      'identified': false,
      'message': '特定できませんでした',
      'mv_outfit': {'status': 'skipped'},
    });

    expect(report.identified, isFalse);
    expect(report.fashion.isEmpty, isTrue);
    expect(report.background.isEmpty, isTrue);
    expect(report.mvOutfit.isOk, isFalse);
    expect(report.sources, isEmpty);
  });

  test('MvVideo.toJson はバックエンドの VideoInfo の形になる', () {
    final video = MvVideo(
      videoId: 'abcDEF12345',
      url: 'https://www.youtube.com/watch?v=abcDEF12345',
      artist: 'YOASOBI',
      songTitle: 'アイドル',
      titleParsed: false,
      title: 'タイトル',
      channelTitle: 'YOASOBI',
      publishedAt: DateTime.utc(2023, 4, 12, 15),
      description: '概要欄',
    );

    final json = video.toJson();

    expect(json['video_id'], 'abcDEF12345');
    expect(json['title_parsed'], isFalse);
    expect(json['published_at'], '2023-04-12T15:00:00.000Z');
    expect(MvVideo.fromJson(json).publishedAt, video.publishedAt);
  });
}
