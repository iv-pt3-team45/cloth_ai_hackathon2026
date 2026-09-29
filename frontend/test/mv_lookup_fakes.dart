import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_repository.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_repository.dart';

/// バックエンドを呼ばないテスト用リポジトリ。受け取った query を記録する。
class FakeMvRepository implements MvRepository {
  FakeMvRepository(this.respond);

  final Future<MvLookupResult> Function(String query) respond;
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
