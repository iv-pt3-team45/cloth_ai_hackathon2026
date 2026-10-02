import 'culture_models.dart';
import 'live_models.dart';
import 'mv_models.dart';

/// MV 検索タブの状態の要約(spec 011)。
///
/// 確認タブに渡すため、MV 検索画面が状態を変えるたびに外へ出す(`MvLookupScreen.onChanged`)。
class MvLookupSnapshot {
  const MvLookupSnapshot({
    this.mvQuery = '',
    this.video,
    this.culture,
    this.cultureLoading = false,
    this.liveQuery = '',
    this.liveDate,
    this.liveResult,
    this.selectedLive,
  });

  /// 最後に実行した MV の入力(MV 名または URL)
  final String mvQuery;

  /// 表示中の動画(候補を閉じている間は null)
  final MvVideo? video;

  /// 表示中の動画のカルチャー情報(取得前・失敗時は null)
  final CultureReport? culture;
  final bool cultureLoading;

  /// 最後に実行したライブ検索の条件
  final String liveQuery;
  final DateTime? liveDate;
  final LiveSearchResult? liveResult;

  /// ライブの候補から選んだ 1 件
  final LiveCandidate? selectedLive;

  /// 表示中の動画のアーティスト。カルチャー情報で特定した名前を優先し、
  /// 無ければタイトルを分解できた場合の名前を使う(spec 009)。
  String? get artist {
    final video = this.video;
    if (video == null) return null;
    final culture = this.culture;
    if (culture != null && culture.identified && culture.artist.isNotEmpty) {
      return culture.artist;
    }
    return video.titleParsed ? video.artist : null;
  }
}
