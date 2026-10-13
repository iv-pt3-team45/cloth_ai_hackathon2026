import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/mv_lookup/culture_repository.dart';
import '../features/mv_lookup/live_repository.dart';
import '../features/mv_lookup/mv_lookup_panel.dart';
import '../features/mv_lookup/mv_lookup_snapshot.dart';
import '../features/mv_lookup/mv_repository.dart';
import '../features/mv_lookup/venue_repository.dart';
import '../features/outfit/outfit_controller.dart';
import '../features/outfit/outfit_progress_view.dart';
import '../features/outfit/outfit_repository.dart';
import '../features/outfit/outfit_result_view.dart';
import '../features/privacy/privacy_policy_screen.dart';
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
  });

  // テストで差し替える
  final MvRepository? mvRepository;
  final CultureRepository? cultureRepository;
  final LiveRepository? liveRepository;
  final VenueRepository? venueRepository;
  final WardrobeRepository? wardrobeRepository;
  final PhotoPicker? photoPicker;
  final OutfitRepository? outfitRepository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
  void dispose() {
    _outfit
      ..removeListener(_onOutfitChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onOutfitChanged() {
    if (mounted) setState(() {});
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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(phase: _phase),
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
                        WardrobeSection(
                          repository: _wardrobe,
                          picker: widget.photoPicker,
                          onChanged: (c) => setState(() => _clothes = c),
                        ),
                        // 初期ページの一番下に小さく置く(spec 042)
                        const PrivacyPolicyLink(),
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
                      imageUrl: _wardrobe.imageUrl,
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
                      imageUrl: _wardrobe.imageUrl,
                      onRetryImage: _outfit.retryImage,
                      onRestart: _restart,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _phase == Phase.input
          ? _SubmitBar(items: checklist, onSubmit: _submit)
          : null,
    );
  }
}

/// ヘッダー(アイコン・アプリ名・説明・段階)。
class _Header extends StatelessWidget {
  const _Header({required this.phase});

  final Phase phase;

  @override
  Widget build(BuildContext context) {
    final current = _phases.indexWhere((p) => p.$1 == phase);
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
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accent2],
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
                  Text(
                    'はじめてのライブ服',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Hint('行くライブと手持ちの服から、会場で浮かないコーディネートを提案します。'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (i, (_, label)) in _phases.indexed)
              Semantics(
                selected: i == current,
                child: Pill(
                  '${i + 1} $label',
                  color: i == current
                      ? AppColors.accent
                      : (i < current ? AppColors.soft : Colors.white),
                  textColor: i == current ? Colors.white : AppColors.muted,
                  bold: i == current,
                ),
              ),
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
                            backgroundColor: AppColors.accent.withValues(
                              alpha: 0.55,
                            ),
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
