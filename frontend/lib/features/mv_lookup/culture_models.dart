import 'utils.dart';

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

  /// バックエンドの CultureResponse の形(コーデ提案に送り返す。spec 011)。
  Map<String, dynamic> toJson() => {
    'artist': artist,
    'identified': identified,
    'message': message,
    'fashion': fashion.toJson(),
    'background': background.toJson(),
    'mv_outfit': mvOutfit.toJson(),
    'sources': sources.map((s) => s.toJson()).toList(),
    'search_suggestions_html': searchSuggestionsHtml,
    'web_search_queries': webSearchQueries,
    'model': model,
  };

  factory CultureReport.fromJson(Map<String, dynamic> json) => CultureReport(
    artist: json['artist'] as String? ?? '',
    identified: json['identified'] as bool? ?? false,
    message: json['message'] as String? ?? '',
    fashion: FashionInfo.fromJson(jsonMap(json['fashion'])),
    background: BackgroundInfo.fromJson(jsonMap(json['background'])),
    mvOutfit: MvOutfit.fromJson(jsonMap(json['mv_outfit'])),
    sources: jsonList(
      json['sources'],
    ).map((s) => CultureSource.fromJson(jsonMap(s))).toList(),
    searchSuggestionsHtml: json['search_suggestions_html'] as String? ?? '',
    webSearchQueries: jsonStrings(json['web_search_queries']),
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

  Map<String, dynamic> toJson() => {
    'styles': styles,
    'colors': colors,
    'items': items,
    'worldview': worldview,
    'source_indices': sourceIndices,
  };

  factory FashionInfo.fromJson(Map<String, dynamic> json) => FashionInfo(
    styles: jsonStrings(json['styles']),
    colors: jsonStrings(json['colors']),
    items: jsonStrings(json['items']),
    worldview: json['worldview'] as String? ?? '',
    sourceIndices: jsonInts(json['source_indices']),
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

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'history': history,
    'genres': genres,
    'representative_songs': representativeSongs,
    'musical_traits': musicalTraits,
    'source_indices': sourceIndices,
  };

  factory BackgroundInfo.fromJson(Map<String, dynamic> json) => BackgroundInfo(
    summary: json['summary'] as String? ?? '',
    history: jsonStrings(json['history']),
    genres: jsonStrings(json['genres']),
    representativeSongs: jsonStrings(json['representative_songs']),
    musicalTraits: json['musical_traits'] as String? ?? '',
    sourceIndices: jsonInts(json['source_indices']),
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

  Map<String, dynamic> toJson() => {
    'status': status,
    'message': message,
    'looks': looks.map((l) => l.toJson()).toList(),
  };

  factory MvOutfit.fromJson(Map<String, dynamic> json) => MvOutfit(
    status: json['status'] as String? ?? 'skipped',
    message: json['message'] as String? ?? '',
    looks: jsonList(
      json['looks'],
    ).map((l) => OutfitLook.fromJson(jsonMap(l))).toList(),
  );
}

/// MV の衣装 1 着分(シーンごと)。
class OutfitLook {
  const OutfitLook({this.label = '', this.items = const []});

  final String label;
  final List<OutfitItem> items;

  Map<String, dynamic> toJson() => {
    'label': label,
    'items': items.map((i) => i.toJson()).toList(),
  };

  factory OutfitLook.fromJson(Map<String, dynamic> json) => OutfitLook(
    label: json['label'] as String? ?? '',
    items: jsonList(
      json['items'],
    ).map((i) => OutfitItem.fromJson(jsonMap(i))).toList(),
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

  Map<String, dynamic> toJson() => {
    'category': category,
    'material': material,
    'shape': shape,
    'colors': colors,
    'pattern': pattern,
    'style': style,
    'notes': notes,
  };

  factory OutfitItem.fromJson(Map<String, dynamic> json) => OutfitItem(
    category: json['category'] as String? ?? '',
    material: json['material'] as String? ?? '',
    shape: json['shape'] as String? ?? '',
    colors: jsonStrings(json['colors']),
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

  Map<String, dynamic> toJson() => {
    'index': index,
    'title': title,
    'url': url,
    'domain': domain,
  };

  factory CultureSource.fromJson(Map<String, dynamic> json) => CultureSource(
    index: json['index'] as int,
    title: json['title'] as String? ?? '',
    url: json['url'] as String? ?? '',
    domain: json['domain'] as String? ?? '',
  );
}
