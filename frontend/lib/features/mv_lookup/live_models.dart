import 'culture_models.dart';
import 'utils.dart';

/// ライブ情報の検索結果(spec 009)。バックエンドの LiveSearchResponse と対応する。
class LiveSearchResult {
  const LiveSearchResult({
    required this.found,
    this.artist = '',
    this.message = '',
    this.candidates = const [],
    this.sources = const [],
    this.searchSuggestionsHtml = '',
    this.webSearchQueries = const [],
    this.model = '',
  });

  /// 検索の条件にしたアーティスト名(表示中の動画から。無ければ空)
  final String artist;
  final bool found;

  /// 見つからなかった場合の理由
  final String message;

  /// 最大 3 件
  final List<LiveCandidate> candidates;
  final List<CultureSource> sources;

  /// Google 検索の検索候補(加工せずに表示する HTML)
  final String searchSuggestionsHtml;
  final List<String> webSearchQueries;
  final String model;

  factory LiveSearchResult.fromJson(Map<String, dynamic> json) =>
      LiveSearchResult(
        artist: json['artist'] as String? ?? '',
        found: json['found'] as bool? ?? false,
        message: json['message'] as String? ?? '',
        candidates: jsonList(
          json['candidates'],
        ).map((c) => LiveCandidate.fromJson(jsonMap(c))).toList(),
        sources: jsonList(
          json['sources'],
        ).map((s) => CultureSource.fromJson(jsonMap(s))).toList(),
        searchSuggestionsHtml: json['search_suggestions_html'] as String? ?? '',
        webSearchQueries: jsonStrings(json['web_search_queries']),
        model: json['model'] as String? ?? '',
      );
}

/// ライブの候補 1 件(1 公演日)。
class LiveCandidate {
  const LiveCandidate({
    required this.index,
    required this.weather,
    this.artist,
    this.liveName = '',
    this.venue = '',
    this.location = '',
    this.date,
    this.sourceIndices = const [],
  });

  /// 候補の番号(1 始まり)。選択の識別にも使う
  final int index;

  /// アーティスト名。表示中の動画でアーティストが分かっている場合は null
  final String? artist;
  final String liveName;
  final String venue;

  /// 所在地(都道府県・市区町村)
  final String location;
  final DateTime? date;
  final LiveWeather weather;
  final List<int> sourceIndices;

  factory LiveCandidate.fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    return LiveCandidate(
      index: json['index'] as int,
      artist: json['artist'] as String?,
      liveName: json['live_name'] as String? ?? '',
      venue: json['venue'] as String? ?? '',
      location: json['location'] as String? ?? '',
      date: date is String ? DateTime.tryParse(date) : null,
      weather: LiveWeather.fromJson(jsonMap(json['weather'])),
      sourceIndices: jsonInts(json['source_indices']),
    );
  }
}

/// 公演当日の天気。
class LiveWeather {
  const LiveWeather({
    required this.kind,
    this.summary = '',
    this.highC,
    this.lowC,
    this.precipitationChance,
  });

  /// 'actual'(実績)/ 'forecast'(予報)/ 'not_yet'(予報はまだ無い)/ 'unknown'(不明)
  final String kind;
  final String summary;
  final double? highC;
  final double? lowC;
  final int? precipitationChance;

  /// 例: 「晴れ / 最高 27℃ / 最低 18℃ / 降水確率 20%(実績)」
  String get description {
    if (kind == 'not_yet') return '予報はまだありません';
    if (kind != 'actual' && kind != 'forecast') return '不明';
    final parts = [
      if (summary.isNotEmpty) summary,
      if (highC != null) '最高 ${_degrees(highC!)}℃',
      if (lowC != null) '最低 ${_degrees(lowC!)}℃',
      if (precipitationChance != null) '降水確率 $precipitationChance%',
    ];
    final label = kind == 'actual' ? '実績' : '予報';
    return parts.isEmpty ? '不明($label)' : '${parts.join(' / ')}($label)';
  }

  static String _degrees(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  factory LiveWeather.fromJson(Map<String, dynamic> json) => LiveWeather(
    kind: json['kind'] as String? ?? 'unknown',
    summary: json['summary'] as String? ?? '',
    highC: (json['high_c'] as num?)?.toDouble(),
    lowC: (json['low_c'] as num?)?.toDouble(),
    precipitationChance: (json['precipitation_chance'] as num?)?.toInt(),
  );
}
