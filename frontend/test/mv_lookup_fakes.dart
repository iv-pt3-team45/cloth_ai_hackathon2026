import 'package:flutter/material.dart';
import 'package:tx_hackathon_gc/core/theme.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_repository.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_repository.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_repository.dart';

/// ライブ情報の検索条件(フェイクが受け取った値)。
typedef LiveRequest = ({String query, DateTime? date, String? artist});

/// Gemini(バックエンド)を呼ばないライブ情報のリポジトリ。受け取った条件を記録する。
class FakeLiveRepository implements LiveRepository {
  FakeLiveRepository([this.respond = _threeLives]);

  final Future<LiveSearchResult> Function(LiveRequest request) respond;
  final requests = <LiveRequest>[];

  @override
  Future<LiveSearchResult> search({
    required String query,
    DateTime? date,
    String? artist,
  }) {
    final request = (query: query, date: date, artist: artist);
    requests.add(request);
    return respond(request);
  }
}

Future<LiveSearchResult> _threeLives(LiveRequest request) async =>
    liveResult(artistKnown: request.artist != null);

/// 3 件の候補(過去の実績 / 予報 / 予報がまだ無い)。
LiveSearchResult liveResult({bool artistKnown = true}) => LiveSearchResult(
  artist: artistKnown ? 'YOASOBI' : '',
  found: true,
  candidates: [
    LiveCandidate(
      index: 1,
      artist: artistKnown ? null : 'YOASOBI',
      liveName: '公演A',
      venue: 'さいたまスーパーアリーナ',
      location: '埼玉県さいたま市',
      date: DateTime(2023, 6, 4),
      weather: const LiveWeather(
        kind: 'actual',
        summary: '晴れ',
        highC: 27,
        lowC: 18,
      ),
      sourceIndices: const [1],
    ),
    LiveCandidate(
      index: 2,
      artist: artistKnown ? null : 'YOASOBI',
      liveName: '公演B',
      venue: '東京ドーム',
      location: '東京都文京区',
      date: DateTime(2026, 10, 3),
      weather: const LiveWeather(
        kind: 'forecast',
        summary: '雨',
        precipitationChance: 80,
      ),
    ),
    LiveCandidate(
      index: 3,
      artist: artistKnown ? null : 'YOASOBI',
      liveName: '公演C',
      venue: '京セラドーム大阪',
      date: DateTime(2027, 1, 10),
      weather: const LiveWeather(kind: 'not_yet'),
    ),
  ],
  sources: const [
    CultureSource(index: 1, title: 'ライブ記事', url: 'https://example.com/live'),
  ],
  searchSuggestionsHtml: '<div>検索候補</div>',
  webSearchQueries: const ['YOASOBI ライブ 2023'],
);

/// バックエンドを呼ばないテスト用リポジトリ。受け取った query を記録する。
class FakeMvRepository implements MvRepository {
  FakeMvRepository(this.respond);

  Future<MvLookupResult> Function(String query) respond;
  final queries = <String>[];

  @override
  Future<MvLookupResult> lookup(String query) {
    queries.add(query);
    return respond(query);
  }
}

/// Gemini(バックエンド)を呼ばないカルチャー情報のリポジトリ。受け取った動画を記録する。
class FakeCultureRepository implements CultureRepository {
  FakeCultureRepository([this.respond = _minimalReport]);

  final Future<CultureReport> Function(MvVideo video) respond;
  final videos = <MvVideo>[];

  @override
  Future<CultureReport> research(MvVideo video) {
    videos.add(video);
    return respond(video);
  }
}

Future<CultureReport> _minimalReport(MvVideo video) async =>
    const CultureReport(artist: 'YOASOBI', identified: true);

const fullReport = CultureReport(
  artist: 'YOASOBI',
  identified: true,
  fashion: FashionInfo(
    styles: ['ストリート'],
    colors: ['黒', '白'],
    items: ['ベレー帽'],
    worldview: 'アニメーションと実写の融合',
    sourceIndices: [1, 2],
  ),
  background: BackgroundInfo(
    summary: '小説を音楽にするユニット',
    history: ['2019年 結成'],
    genres: ['J-POP'],
    representativeSongs: ['夜に駆ける'],
    sourceIndices: [1],
  ),
  mvOutfit: MvOutfit(
    status: 'ok',
    looks: [
      OutfitLook(
        label: 'メインの衣装',
        items: [
          OutfitItem(
            category: 'ワンピース',
            colors: ['白'],
            style: 'ガーリー',
            shape: 'ミニ丈',
            notes: 'フリル',
          ),
        ],
      ),
    ],
  ),
  sources: [
    CultureSource(
      index: 1,
      title: '記事A',
      url: 'https://example.com/a',
      domain: 'example.com',
    ),
    CultureSource(
      index: 2,
      title: '記事B',
      url: 'https://example.org/b',
      domain: 'example.org',
    ),
    CultureSource(
      index: 3,
      title: 'example.net',
      url: 'https://example.net/c',
      domain: 'example.net',
    ),
  ],
  searchSuggestionsHtml: '<div>検索候補</div>',
  webSearchQueries: ['YOASOBI ファッション'],
);

/// 入力の段階と同じく、パネルを 1 本のスクロールの中に置く(spec 015)。
Widget panelApp(Widget panel) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: panel,
    ),
  ),
);
