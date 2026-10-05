import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../mv_lookup/culture_models.dart';
import '../mv_lookup/live_models.dart';
import '../mv_lookup/mv_models.dart';
import 'outfit_models.dart';
import 'outfit_repository.dart';

/// コーデ提案の進み具合(spec 015)。
enum OutfitStage {
  /// 何もしていない(提案の失敗・キャンセルの後もここに戻る)
  idle,

  /// ① 手持ちの服からコーデを考えている
  suggesting,

  /// ② マネキンに着せた画像を作っている
  imaging,

  /// 提案と画像の生成が終わった(画像だけの失敗を含む)
  done,
}

/// コーデ提案(spec 011)の処理: 提案 → 画像の生成、画像の作り直し、キャンセル。
///
/// 画面(進捗・結果)はこの状態を見て切り替える。キャンセルはバックエンドの処理を止めず、
/// 後から届いた結果を世代番号で捨てる(spec 015 AC-9)。
class OutfitController extends ChangeNotifier {
  OutfitController({OutfitRepository? repository})
    : _repository = repository ?? OutfitRepository();

  final OutfitRepository _repository;

  OutfitStage _stage = OutfitStage.idle;
  OutfitStage get stage => _stage;

  OutfitSuggestion? _suggestion;
  OutfitSuggestion? get suggestion => _suggestion;

  OutfitImage? _image;
  OutfitImage? get image => _image;

  String? _imageError;

  /// 画像の生成だけが失敗したときの理由(提案は残す。spec 011 AC-13)
  String? get imageError => _imageError;

  String? _error;

  /// 提案の失敗の理由(入力の段階の上部に出す)
  String? get error => _error;

  bool _retryingImage = false;

  /// 結果の画面で画像を作り直している
  bool get retryingImage => _retryingImage;

  DateTime? _startedAt;

  /// 提案を始めた時刻(経過時間の表示用)
  DateTime? get startedAt => _startedAt;

  bool get running =>
      _stage == OutfitStage.suggesting || _stage == OutfitStage.imaging;

  int _generation = 0;
  bool _disposed = false;

  /// ① 提案 → ② 画像の生成 を続けて行う。前の結果は消してやり直す(spec 011 AC-14)。
  Future<void> run({
    required MvVideo video,
    required LiveCandidate live,
    CultureReport? culture,
  }) async {
    final generation = ++_generation;
    _stage = OutfitStage.suggesting;
    _suggestion = null;
    _image = null;
    _imageError = null;
    _error = null;
    _retryingImage = false;
    _startedAt = DateTime.now();
    _notify();

    final OutfitSuggestion suggestion;
    try {
      suggestion = await _repository.suggest(
        video: video,
        live: live,
        culture: culture,
      );
    } on ApiException catch (e) {
      _fail(generation, e.detail);
      return;
    } on Exception {
      _fail(generation, 'サーバーに接続できませんでした');
      return;
    }
    if (generation != _generation) return;
    _suggestion = suggestion;
    _stage = OutfitStage.imaging;
    _notify();

    await _generateImage(generation, suggestion);
    if (generation != _generation) return;
    _stage = OutfitStage.done;
    _notify();
  }

  /// 画像だけを作り直す(結果の画面の「画像を作り直す」)。
  Future<void> retryImage() async {
    final suggestion = _suggestion;
    if (suggestion == null || running || _retryingImage) return;
    final generation = _generation;
    _retryingImage = true;
    _image = null;
    _imageError = null;
    _notify();
    await _generateImage(generation, suggestion);
    if (generation != _generation) return;
    _retryingImage = false;
    _notify();
  }

  /// 提案を取りやめる。後から届いた結果は捨てる。
  void cancel() {
    _generation++;
    _stage = OutfitStage.idle;
    _suggestion = null;
    _image = null;
    _imageError = null;
    _error = null;
    _retryingImage = false;
    _notify();
  }

  Future<void> _generateImage(
    int generation,
    OutfitSuggestion suggestion,
  ) async {
    try {
      final image = await _repository.generateImage(
        itemIds: [for (final item in suggestion.items) item.cloth.id],
        title: suggestion.title,
      );
      if (generation == _generation) _image = image;
    } on ApiException catch (e) {
      if (generation == _generation) _imageError = e.detail;
    } on Exception {
      if (generation == _generation) _imageError = 'サーバーに接続できませんでした';
    }
  }

  void _fail(int generation, String message) {
    if (generation != _generation) return;
    _error = message;
    _stage = OutfitStage.idle;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
