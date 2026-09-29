/// アーティストのカルチャー情報(spec 008)。バックエンドの CultureResponse と対応する。
class CultureReport {
  const CultureReport({
    required this.artist,
    required this.identified,
    this.message = '',
    this.fashion = const FashionInfo(),
    this.background = const BackgroundInfo(),
    this.mvOutfit = const MvOutfit(status: 'skipped'),
    this.sources = const [],
    this.searchSuggestionsHtml = '',
    this.webSearchQueries = const [],
    this.model = '',
  });

  /// Gemini が特定したアーティスト名
  final String artist;

  /// アーティストを特定できたか
  final bool identified;

  /// 特定できなかった場合の理由
  final String message;

  final FashionInfo fashion;
  final BackgroundInfo background;
  final MvOutfit mvOutfit;
  final List<CultureSource> sources;

  /// Google 検索の検索候補(加工せずに表示する HTML)
  final String searchSuggestionsHtml;

  /// 実行された検索クエリ
  final List<String> webSearchQueries;
  final String model;

  factory CultureReport.fromJson(Map<String, dynamic> json) => CultureReport(
    artist: json['artist'] as String? ?? '',
    identified: json['identified'] as bool? ?? false,
    message: json['message'] as String? ?? '',
    fashion: FashionInfo.fromJson(_map(json['fashion'])),
    background: BackgroundInfo.fromJson(_map(json['background'])),
    mvOutfit: MvOutfit.fromJson(_map(json['mv_outfit'])),
    sources: _list(
      json['sources'],
    ).map((s) => CultureSource.fromJson(_map(s))).toList(),
    searchSuggestionsHtml: json['search_suggestions_html'] as String? ?? '',
    webSearchQueries: _strings(json['web_search_queries']),
    model: json['model'] as String? ?? '',
  );
}

/// ファッション・ビジュアル(Web 検索が根拠)。
class FashionInfo {
  const FashionInfo({
    this.styles = const [],
    this.colors = const [],
    this.items = const [],
    this.worldview = '',
    this.sourceIndices = const [],
  });

  final List<String> styles;
  final List<String> colors;
  final List<String> items;
  final String worldview;
  final List<int> sourceIndices;

  bool get isEmpty =>
      styles.isEmpty && colors.isEmpty && items.isEmpty && worldview.isEmpty;

  factory FashionInfo.fromJson(Map<String, dynamic> json) => FashionInfo(
    styles: _strings(json['styles']),
    colors: _strings(json['colors']),
    items: _strings(json['items']),
    worldview: json['worldview'] as String? ?? '',
    sourceIndices: _ints(json['source_indices']),
  );
}

/// 経歴・音楽性(Web 検索が根拠)。
class BackgroundInfo {
  const BackgroundInfo({
    this.summary = '',
    this.history = const [],
    this.genres = const [],
    this.representativeSongs = const [],
    this.musicalTraits = '',
    this.sourceIndices = const [],
  });

  final String summary;
  final List<String> history;
  final List<String> genres;
  final List<String> representativeSongs;
  final String musicalTraits;
  final List<int> sourceIndices;

  bool get isEmpty =>
      summary.isEmpty &&
      history.isEmpty &&
      genres.isEmpty &&
      representativeSongs.isEmpty &&
      musicalTraits.isEmpty;

  factory BackgroundInfo.fromJson(Map<String, dynamic> json) => BackgroundInfo(
    summary: json['summary'] as String? ?? '',
    history: _strings(json['history']),
    genres: _strings(json['genres']),
    representativeSongs: _strings(json['representative_songs']),
    musicalTraits: json['musical_traits'] as String? ?? '',
    sourceIndices: _ints(json['source_indices']),
  );
}

/// この MV の衣装(MV の映像が根拠)。
class MvOutfit {
  const MvOutfit({
    required this.status,
    this.message = '',
    this.looks = const [],
  });

  /// 'ok' / 'unavailable'(解析できなかった)/ 'skipped'(使わなかった)
  final String status;
  final String message;
  final List<OutfitLook> looks;

  bool get isOk => status == 'ok';

  factory MvOutfit.fromJson(Map<String, dynamic> json) => MvOutfit(
    status: json['status'] as String? ?? 'skipped',
    message: json['message'] as String? ?? '',
    looks: _list(
      json['looks'],
    ).map((l) => OutfitLook.fromJson(_map(l))).toList(),
  );
}

/// MV の衣装 1 着分(シーンごと)。
class OutfitLook {
  const OutfitLook({this.label = '', this.items = const []});

  final String label;
  final List<OutfitItem> items;

  factory OutfitLook.fromJson(Map<String, dynamic> json) => OutfitLook(
    label: json['label'] as String? ?? '',
    items: _list(
      json['items'],
    ).map((i) => OutfitItem.fromJson(_map(i))).toList(),
  );
}

/// MV で着ている服 1 点。項目は服インデックス(spec 005)と揃えている。
class OutfitItem {
  const OutfitItem({
    this.category = '',
    this.material = '',
    this.shape = '',
    this.colors = const [],
    this.pattern = '',
    this.style = '',
    this.notes = '',
  });

  final String category;
  final String material;
  final String shape;
  final List<String> colors;
  final String pattern;
  final String style;
  final String notes;

  factory OutfitItem.fromJson(Map<String, dynamic> json) => OutfitItem(
    category: json['category'] as String? ?? '',
    material: json['material'] as String? ?? '',
    shape: json['shape'] as String? ?? '',
    colors: _strings(json['colors']),
    pattern: json['pattern'] as String? ?? '',
    style: json['style'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
  );
}

/// Web 検索の出典。[index] は各セクションの sourceIndices から参照される。
class CultureSource {
  const CultureSource({
    required this.index,
    required this.title,
    required this.url,
    this.domain = '',
  });

  final int index;
  final String title;
  final String url;
  final String domain;

  factory CultureSource.fromJson(Map<String, dynamic> json) => CultureSource(
    index: json['index'] as int,
    title: json['title'] as String? ?? '',
    url: json['url'] as String? ?? '',
    domain: json['domain'] as String? ?? '',
  );
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<dynamic> _list(Object? value) => value is List ? value : const [];

List<String> _strings(Object? value) =>
    _list(value).whereType<String>().toList();

List<int> _ints(Object? value) => _list(value).whereType<int>().toList();
