import '../../core/api_client.dart';
import 'mv_models.dart';

/// MV 検索機能のデータアクセス層。
class MvRepository {
  MvRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// YouTube の URL または MV 名から、動画情報または候補一覧を得る。
  ///
  /// 候補を選んだときは、候補の URL を [query] に渡して呼び直す。
  Future<MvLookupResult> lookup(String query) async {
    final json = await _client.post('/youtube/lookup', {'query': query});
    return MvLookupResult.fromJson(json);
  }
}
