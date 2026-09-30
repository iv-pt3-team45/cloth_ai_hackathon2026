import '../../core/api_client.dart';
import 'live_models.dart';
import 'utils.dart';

/// ライブ情報の検索(spec 009)のデータアクセス層。
class LiveRepository {
  LiveRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// 条件に合うライブを最大 3 件、当日の天気とともに Gemini に調べさせる(数十秒かかる)。
  ///
  /// [artist] は表示中の動画で分かっているアーティスト名。渡すとそのアーティストの公演だけを探し、
  /// 候補ごとのアーティスト名は取得しない。
  Future<LiveSearchResult> search({
    required String query,
    DateTime? date,
    String? artist,
  }) async {
    final json = await _client.post('/live/search', {
      'query': query,
      if (date != null) 'date': isoDate(date),
      'artist': ?artist,
    });
    return LiveSearchResult.fromJson(json);
  }
}
