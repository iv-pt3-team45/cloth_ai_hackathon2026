import 'package:flutter/material.dart';

import '../core/auth_session.dart';
import '../core/reduce_motion.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/auth/login_card.dart';
import '../features/mv_lookup/culture_repository.dart';
import '../features/mv_lookup/culture_vibe.dart';
import '../features/mv_lookup/live_repository.dart';
import '../features/mv_lookup/mv_lookup_panel.dart';
import '../features/mv_lookup/mv_lookup_snapshot.dart';
import '../features/mv_lookup/mv_repository.dart';
import '../features/mv_lookup/venue_repository.dart';
import '../features/mv_lookup/vibe_backdrop.dart';
import '../features/outfit/outfit_controller.dart';
import '../features/outfit/outfit_models.dart';
import '../features/outfit/outfit_progress_view.dart';
import '../features/outfit/outfit_repository.dart';
import '../features/outfit/outfit_result_view.dart';
import '../features/wardrobe/photo_picker.dart';
import '../features/wardrobe/wardrobe_models.dart';
import '../features/wardrobe/wardrobe_repository.dart';
import '../features/wardrobe/wardrobe_section.dart';

/// 画面の段階(spec 015)。
enum Phase { input, running, result }

const _phases = [
  (Phase.input, '入力'),
  (Phase.running, 'AIが考え中'),
  (Phase.result, '提案'),
];

/// 結果を受け取ってから「できました」を見せ、結果の画面に切り替えるまでの時間
const donePause = Duration(milliseconds: 900);

typedef _Check = ({bool ok, String label, String error});

/// 1 画面で「1 入力」→「2 AIが考え中」→「3 提案」と進むアプリの画面(spec 015)。
///
/// 各 feature のカード・画面を組み立てる層。feature どうしは直接つながず、
/// MV・ライブの要約(MvLookupSnapshot)と手持ちの服の一覧をここで受け取って提案に渡す。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.mvRepository,
    this.cultureRepository,
    this.liveRepository,
    this.venueRepository,
    this.wardrobeRepository,
    this.photoPicker,
    this.outfitRepository,
    this.authSession,
  });

  // テストで差し替える
  final MvRepository? mvRepository;
  final CultureRepository? cultureRepository;
  final LiveRepository? liveRepository;
  final VenueRepository? venueRepository;
  final WardrobeRepository? wardrobeRepository;
  final PhotoPicker? photoPicker;
  final OutfitRepository? outfitRepository;

  /// ログインの状態(spec 038)。省略時はアプリで 1 つの状態
  final AuthSession? authSession;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AuthSession _auth = (widget.authSession ?? AuthSession.shared)
    ..addListener(_onAuthChanged);
  late String _owner = _auth.ownerKey;

  /// ヘッダの「ログイン」を押した回数(③ のログインの入力欄を開く)
  int _loginRequest = 0;
  final _wardrobeKey = GlobalKey();
  late final WardrobeRepository _wardrobe =
      widget.wardrobeRepository ?? WardrobeRepository();
  late final OutfitController _outfit = OutfitController(
    repository: widget.outfitRepository,
  )..addListener(_onOutfitChanged);
  final _scroll = ScrollController();

  Phase _phase = Phase.input;
  MvLookupSnapshot _snapshot = const MvLookupSnapshot();
  List<RegisteredCloth>? _clothes;

  /// 一度提案ボタンを押したら、足りないものを入力に合わせてその場で更新する
  bool _attempted = false;
  String? _notice;

  /// 提案の実行の番号(キャンセル後に前の実行の続きを捨てる)
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _auth.restore();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _outfit
      ..removeListener(_onOutfitChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onOutfitChanged() {
    if (mounted) setState(() {});
  }

  /// ログイン・ログアウトしたら、手持ちの服を読み直し、前の持ち主の服で作った提案を消す。
  /// ① ② の入力と選択は残す(spec 038 AC-12)。
  void _onAuthChanged() {
    if (!mounted) return;
    final owner = _auth.ownerKey;
    if (owner == _owner) {
      setState(() {});
      return;
    }
    _owner = owner;
    if (_phase != Phase.input) {
      _run++;
      _outfit.cancel();
    }
    setState(() {
      _clothes = null;
      _attempted = false;
      _notice = null;
      _phase = Phase.input;
    });
  }

  /// ヘッダの「ログイン」: ③ のカードまで移動して、ログインの入力欄を開く。
  void _openLogin() {
    setState(() => _loginRequest++);
    final context = _wardrobeKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  List<_Check> get _checklist {
    final clothes = _clothes ?? const [];
    return [
      (ok: _snapshot.video != null, label: 'MV', error: '① で MV を選んでください。'),
      (
        ok: _snapshot.selectedLive != null,
        label: 'ライブの選択',
        error: '② でライブを検索して、行くライブを選んでください。',
      ),
      (
        ok: clothes.isNotEmpty,
        label: '手持ちの服${clothes.isEmpty ? '' : '(${clothes.length}点)'}',
        error: '③ で手持ちの服を 1 点以上登録してください。',
      ),
    ];
  }

  void _setPhase(Phase phase) {
    setState(() => _phase = phase);
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _submit() async {
    setState(() {
      _notice = null;
      _attempted = true;
    });
    final video = _snapshot.video;
    final live = _snapshot.selectedLive;
    if (!_checklist.every((c) => c.ok) ||
        _snapshot.cultureLoading ||
        video == null ||
        live == null) {
      _scrollToTop();
      return;
    }

    final run = ++_run;
    _setPhase(Phase.running);
    await _outfit.run(
      video: video,
      live: live,
      culture: _snapshot.culture,
      // 会場の形態(spec 014)。調べている途中なら送らない(バックエンドが提案の前に調べる)
      venueFormat: _snapshot.venueFormatLoading ? null : _snapshot.venueFormat,
    );
    if (!mounted || run != _run) return;
    if (_outfit.suggestion == null) {
      // 提案の失敗。理由は上部の枠に出す(spec 015 AC-13)
      _setPhase(Phase.input);
      return;
    }
    // 「できました」を少し見せてから結果の画面に切り替える
    await Future<void>.delayed(donePause);
    if (!mounted || run != _run) return;
    _attempted = false;
    _setPhase(Phase.result);
  }

  void _cancel() {
    _run++;
    _outfit.cancel();
    _notice = '提案をキャンセルしました。入力内容はそのまま残っています。';
    _setPhase(Phase.input);
  }

  void _restart() {
    _notice = null;
    _setPhase(Phase.input);
  }

  @override
  Widget build(BuildContext context) {
    final checklist = _checklist;
    final missing = [
      if (_attempted) ...checklist.where((c) => !c.ok).map((c) => c.error),
    ];
    final waitingCulture =
        _attempted && missing.isEmpty && _snapshot.cultureLoading;
    final failure = _phase == Phase.input ? _outfit.error : null;
    final suggestion = _outfit.suggestion;
    // MV のカルチャーに合わせた演出(spec 039)。選択を外せば null になり、標準の配色に戻る
    final vibe = CultureVibe.from(_snapshot.video, _snapshot.culture);
    final reduceMotion = reduceMotionOf(context);

    // 配色は画面全体に掛けるので、「考え中」「提案」の段階とポップアップにも引き継がれる
    return AnimatedTheme(
      data: buildTheme(palette: CultureVibe.paletteOf(vibe)),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 400),
      child: Builder(
        builder: (context) => _buildScaffold(
          context,
          vibe: vibe,
          reduceMotion: reduceMotion,
          checklist: checklist,
          missing: missing,
          waitingCulture: waitingCulture,
          failure: failure,
          suggestion: suggestion,
        ),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required CultureVibe? vibe,
    required bool reduceMotion,
    required List<_Check> checklist,
    required List<String> missing,
    required bool waitingCulture,
    required String? failure,
    required OutfitSuggestion? suggestion,
  }) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.backgroundBottom,
      body: Stack(
        children: [
          // 背景のグラデーションと、カードの後ろで流れる動き
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [palette.backgroundTop, palette.backgroundBottom],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: VibeBackdrop(
              effect: vibe?.effect,
              colors: [palette.accent, palette.accent2],
              animate: !reduceMotion,
            ),
          ),
          SafeArea(
            bottom: false,
            child: _buildBody(
              checklist: checklist,
              missing: missing,
              waitingCulture: waitingCulture,
              failure: failure,
              suggestion: suggestion,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _phase == Phase.input
          ? _SubmitBar(items: checklist, onSubmit: _submit)
          : null,
    );
  }

  Widget _buildBody({
    required List<_Check> checklist,
    required List<String> missing,
    required bool waitingCulture,
    required String? failure,
    required OutfitSuggestion? suggestion,
  }) {
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                phase: _phase,
                account: AccountStatus(
                  session: _auth,
                  onLoginTap: _phase == Phase.input ? _openLogin : null,
                ),
              ),
              const SizedBox(height: 16),
              // 入力の段階のカードは、進捗・結果の段階でも破棄せずに隠すだけにする
              // (入力した内容・選んだ候補・取得中の処理を残すため。spec 015 AC-9, AC-14)
              Visibility(
                visible: _phase == Phase.input,
                maintainState: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_notice != null)
                      MessageBox(
                        color: AppColors.ok,
                        children: [Text(_notice!)],
                      ),
                    // ログインの期限切れなど(spec 038)
                    if (_auth.notice != null)
                      MessageBox(
                        color: AppColors.accent,
                        children: [Text(_auth.notice!)],
                      ),
                    if (missing.isNotEmpty || waitingCulture)
                      MessageBox(
                        color: AppColors.accent,
                        children: [
                          const Text(
                            '入力内容を確認してください',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Bullets([
                            ...missing,
                            if (waitingCulture)
                              'カルチャー情報を調べています。終わってからもう一度押してください。',
                          ]),
                        ],
                      ),
                    if (failure != null)
                      MessageBox(
                        color: AppColors.accent,
                        children: [
                          const Text(
                            'コーデを提案できませんでした',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(failure),
                          const SizedBox(height: 4),
                          const Hint('もう一度「コーディネートを提案してもらう」を押してください。'),
                        ],
                      ),
                    MvLookupPanel(
                      repository: widget.mvRepository,
                      cultureRepository: widget.cultureRepository,
                      liveRepository: widget.liveRepository,
                      venueRepository: widget.venueRepository,
                      onChanged: (s) => setState(() => _snapshot = s),
                    ),
                    // 持ち主(ログイン・ゲスト)が変わったら作り直して一覧を読み直す(spec 038)
                    KeyedSubtree(
                      key: _wardrobeKey,
                      child: WardrobeSection(
                        key: ValueKey(_owner),
                        repository: _wardrobe,
                        picker: widget.photoPicker,
                        onChanged: (c) => setState(() => _clothes = c),
                        header: _auth.isUser
                            ? null
                            : LoginCard(
                                session: _auth,
                                openRequest: _loginRequest,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_phase == Phase.running)
                OutfitProgressView(
                  stage: _outfit.stage,
                  startedAt: _outfit.startedAt ?? DateTime.now(),
                  clothes: suggestion == null
                      ? _clothes ?? const []
                      : [for (final item in suggestion.items) item.cloth],
                  photo: _wardrobe.imageBytes,
                  onCancel: _cancel,
                  imageFailed: _outfit.imageError != null,
                ),
              if (_phase == Phase.result && suggestion != null)
                OutfitResultView(
                  suggestion: suggestion,
                  image: _outfit.image,
                  imageError: _outfit.imageError,
                  retryingImage: _outfit.retryingImage,
                  live: _snapshot.selectedLive,
                  liveResult: _snapshot.liveResult,
                  culture: _snapshot.culture,
                  photo: _wardrobe.imageBytes,
                  onRetryImage: _outfit.retryImage,
                  onRestart: _restart,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ヘッダー(アイコン・アプリ名・説明・段階・ログインの状態)。
class _Header extends StatelessWidget {
  const _Header({required this.phase, required this.account});

  final Phase phase;
  final Widget account;

  @override
  Widget build(BuildContext context) {
    final current = _phases.indexWhere((p) => p.$1 == phase);
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [palette.accent, palette.accent2],
                ),
              ),
              child: const Text(
                '♪',
                style: TextStyle(color: Colors.white, fontSize: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // カードの外の文字なので、暗い背景(spec 039)では白にする
                  Text(
                    'はじめてのライブ服',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: palette.onBackground,
                    ),
                  ),
                  Text(
                    '行くライブと手持ちの服から、会場で浮かないコーディネートを提案します。',
                    style: TextStyle(
                      color: palette.onBackgroundMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (i, (_, label)) in _phases.indexed)
                    Semantics(
                      selected: i == current,
                      child: Pill(
                        '${i + 1} $label',
                        color: i == current
                            ? palette.accent
                            : (i < current ? AppColors.soft : Colors.white),
                        textColor: i == current
                            ? Colors.white
                            : AppColors.muted,
                        bold: i == current,
                      ),
                    ),
                ],
              ),
            ),
            // ログイン中のユーザー名とログアウト / ゲスト(spec 038)
            Flexible(child: account),
          ],
        ),
      ],
    );
  }
}

/// 画面下に固定する送信バー(送信前のチェックリスト付き)。
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.items, required this.onSubmit});

  final List<_Check> items;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final ready = items.every((c) => c.ok);
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Center(
            heightFactor: 1, // 縦に広がって画面全体を覆わないようにする
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      for (final c in items)
                        Semantics(
                          label: '${c.label}${c.ok ? '(OK)' : '(未入力)'}',
                          excludeSemantics: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                c.ok
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 16,
                                color: c.ok ? AppColors.ok : AppColors.border,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                c.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: c.ok
                                      ? AppColors.text
                                      : AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: ready
                        ? null
                        : FilledButton.styleFrom(
                            backgroundColor: AppPalette.of(
                              context,
                            ).accent.withValues(alpha: 0.55),
                          ),
                    onPressed: onSubmit,
                    child: const Text('コーディネートを提案してもらう'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
