import '../../core/api_client.dart';
import '../../core/auth_session.dart';
import '../mv_lookup/culture_models.dart';
import '../mv_lookup/live_models.dart';
import '../mv_lookup/mv_models.dart';
import '../mv_lookup/venue_models.dart';
import 'outfit_models.dart';

/// コーデ提案(spec 011)のデータアクセス層。
///
/// ログイン・ゲストのトークンを付けて呼ぶ(spec 038)。提案にはトークンの持ち主の服だけが使われる。
class OutfitRepository {
  OutfitRepository({ApiClient? client})
    : _client = client ?? ApiClient(auth: AuthSession.shared);

  final ApiClient _client;

  /// 手持ちの服の中から 1 コーデを Gemini に提案させる。
  ///
  /// 手持ちの服はバックエンドが保存先から読むため、ここでは MV・カルチャー・ライブだけを送る。
  /// [venueFormat] はライブを選んだ時点で調べた会場の形態(spec 014)。
  /// 省略するとバックエンドが提案の前に調べる。
  Future<OutfitSuggestion> suggest({
    required MvVideo video,
    required LiveCandidate live,
    CultureReport? culture,
    VenueFormat? venueFormat,
  }) async {
    final json = await _client.post('/outfit/suggest', {
      'video': video.toJson(),
      'culture': culture?.toJson(),
      'live': live.toJson(),
      if (venueFormat != null) 'venue_format': venueFormat.value,
    });
    return OutfitSuggestion.fromJson(json);
  }

  /// 提案の服をマネキンに着せた画像を生成する(服の写真そのものを参照に使う)。
  Future<OutfitImage> generateImage({
    required List<String> itemIds,
    String title = '',
  }) async {
    final json = await _client.post('/outfit/image', {
      'item_ids': itemIds,
      'title': title,
    });
    return OutfitImage.fromJson(json);
  }
}
