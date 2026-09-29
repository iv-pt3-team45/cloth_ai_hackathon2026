import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';

void main() {
  group('MvLookupResult.fromJson', () {
    test('URL を入力した場合は video が入る', () {
      final result = MvLookupResult.fromJson({
        'input_type': 'url',
        'video': {
          'video_id': 'abcDEF12345',
          'url': 'https://www.youtube.com/watch?v=abcDEF12345',
          'artist': 'YOASOBI',
          'song_title': 'アイドル',
          'title_parsed': true,
          'title': 'YOASOBI「アイドル」 Official Music Video',
          'channel_title': 'Ayase / YOASOBI',
          'published_at': '2023-06-15T12:00:00Z',
          'thumbnail_url': 'https://i.ytimg.com/vi/x/hqdefault.jpg',
          'description': '概要欄',
        },
        'candidates': <dynamic>[],
      });

      final video = result.video!;
      expect(result.inputType, 'url');
      expect(result.candidates, isEmpty);
      expect(video.artist, 'YOASOBI');
      expect(video.songTitle, 'アイドル');
      expect(video.titleParsed, isTrue);
      expect(video.publishedAt, DateTime.utc(2023, 6, 15, 12));
      expect(video.description, '概要欄');
    });

    test('MV 名を入力した場合は candidates が入る', () {
      final result = MvLookupResult.fromJson({
        'input_type': 'keyword',
        'video': null,
        'candidates': [
          {
            'video_id': 'video000000',
            'url': 'https://www.youtube.com/watch?v=video000000',
            'title': 'Song',
            'channel_title': 'Channel',
            'published_at': null,
            'thumbnail_url': '',
          },
        ],
      });

      expect(result.video, isNull);
      expect(result.candidates.single.url, contains('video000000'));
      expect(result.candidates.single.publishedAt, isNull);
    });
  });

  group('ApiException.detail', () {
    test('FastAPI の detail を取り出す', () {
      final e = ApiException('{"detail":"動画が見つかりませんでした。"}', statusCode: 404);
      expect(e.detail, '動画が見つかりませんでした。');
    });

    test('入力検証エラー(一覧)はメッセージをつなげる', () {
      final e = ApiException(
        '{"detail":[{"msg":"String should have at least 1 character"}]}',
        statusCode: 422,
      );
      expect(e.detail, 'String should have at least 1 character');
    });

    test('JSON でなければ本文をそのまま返す', () {
      final e = ApiException('Bad Gateway', statusCode: 502);
      expect(e.detail, 'Bad Gateway');
    });
  });
}
