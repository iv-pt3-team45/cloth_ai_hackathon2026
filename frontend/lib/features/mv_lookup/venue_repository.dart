import '../../core/api_client.dart';
import 'live_models.dart';
import 'utils.dart';
import 'venue_models.dart';

/// 会場の形態を調べる(spec 014)データアクセス層。
class VenueRepository {
  VenueRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// 選んだライブの会場の形態を Gemini に調べさせる(数秒〜十数秒かかる)。
  ///
  /// 所在地・ライブ名・公演日は、検索の手がかりとして一緒に送る。
  /// バックエンドは調べられなかったときも unknown を返す(通信エラーは呼び出し側で扱う)。
  Future<VenueFormat> lookup(LiveCandidate live) async {
    final date = live.date;
    final json = await _client.post('/venue/lookup', {
      'venue': live.venue,
      'location': live.location,
      'live_name': live.liveName,
      if (date != null) 'date': isoDate(date),
    });
    return VenueFormat.fromValue(json['format']);
  }
}
