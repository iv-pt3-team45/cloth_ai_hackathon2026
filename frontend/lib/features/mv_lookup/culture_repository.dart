import '../../core/api_client.dart';
import 'culture_models.dart';
import 'mv_models.dart';

/// カルチャー情報(spec 008)のデータアクセス層。
class CultureRepository {
  CultureRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// 動画のアーティストのカルチャー情報を Gemini に調べさせる(数十秒かかる)。
  ///
  /// 結果は使い回さない(Google 検索のグラウンディング結果は保存しない方針のため)。
  Future<CultureReport> research(MvVideo video) async {
    final json = await _client.post('/culture/research', {
      'video': video.toJson(),
    });
    return CultureReport.fromJson(json);
  }
}
