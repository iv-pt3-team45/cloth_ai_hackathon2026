import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../wardrobe/wardrobe_models.dart';
import '../wardrobe/wardrobe_section.dart';
import 'outfit_controller.dart';

String _formatElapsed(int sec) => sec >= 60
    ? '${sec ~/ 60}分${(sec % 60).toString().padLeft(2, '0')}秒'
    : '$sec秒';

/// 「2 AIが考え中」の画面(参考 UI の progress_view.dart から % とバー・豆知識を除いたもの。spec 015)。
///
/// 段階は実際の API の完了に合わせて切り替える: ① コーデを考える → ② 着せた画像を作る。
class OutfitProgressView extends StatefulWidget {
  const OutfitProgressView({
    super.key,
    required this.stage,
    required this.startedAt,
    required this.clothes,
    required this.photo,
    required this.onCancel,
    this.imageFailed = false,
  });

  final OutfitStage stage;
  final DateTime startedAt;

  /// 並べて見せる服(考えている間は手持ちの服すべて、画像を作る間は提案の服)
  final List<RegisteredCloth> clothes;
  final PhotoLoader photo;
  final VoidCallback onCancel;

  /// 画像の生成だけが失敗した(終わったときの見出しと段階 2 の表示に使う)
  final bool imageFailed;

  @override
  State<OutfitProgressView> createState() => _OutfitProgressViewState();
}

class _OutfitProgressViewState extends State<OutfitProgressView> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage;
    final done = stage == OutfitStage.done;
    final elapsed = max(0, _now.difference(widget.startedAt).inSeconds);
    final headline = switch (stage) {
      OutfitStage.done when widget.imageFailed => 'コーデはできましたが、画像は作れませんでした',
      OutfitStage.done => 'コーディネートができました!',
      OutfitStage.imaging => 'マネキンに着せた画像を作っています',
      _ => '手持ちの服から、行くライブに合うコーデを考えています',
    };
    final imaging = stage == OutfitStage.imaging || done;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          children: [
            SizedBox(
              height: 64,
              child: done
                  ? Icon(
                      widget.imageFailed ? Icons.error : Icons.check_circle,
                      color: widget.imageFailed ? AppColors.ng : AppColors.ok,
                      size: 56,
                    )
                  : const _Equalizer(),
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                headline,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Hint(
                '経過 ${_formatElapsed(elapsed)}${done ? '' : ' ・ 目安 30秒〜1分'}',
              ),
            ),
            if (!done) ...[
              const SizedBox(height: 4),
              const Center(child: Hint('完了まで、この画面を開いたままお待ちください')),
            ],
            if (elapsed >= 150 && !done) ...[
              const SizedBox(height: 8),
              const ErrorText('いつもより時間がかかっています。画面を閉じずにそのままお待ちください。'),
            ],
            if (widget.clothes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                imaging
                    ? 'コーデに使う服 ${widget.clothes.length}点'
                    : '手持ちの服 ${widget.clothes.length}点から選んでいます',
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.clothes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox.square(
                      dimension: 48,
                      child: ClothPhoto(
                        image: widget.clothes[i].image,
                        load: widget.photo,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _StageRow(
              index: 0,
              title: 'コーデを考える',
              state: stage == OutfitStage.suggesting
                  ? _RowState.active
                  : _RowState.done,
            ),
            _StageRow(
              index: 1,
              title: '着せた画像を作る',
              state: switch (stage) {
                OutfitStage.imaging => _RowState.active,
                OutfitStage.done when widget.imageFailed => _RowState.failed,
                OutfitStage.done => _RowState.done,
                _ => _RowState.pending,
              },
            ),
          ],
        ),
        if (!done)
          Center(
            child: OutlinedButton(
              onPressed: widget.onCancel,
              child: const Text('キャンセルして入力に戻る'),
            ),
          ),
      ],
    );
  }
}

enum _RowState { done, active, pending, failed }

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.index,
    required this.title,
    required this.state,
  });

  final int index;
  final String title;
  final _RowState state;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      _RowState.failed => const Icon(
        Icons.error,
        color: AppColors.ng,
        size: 24,
      ),
      _RowState.done => const Icon(
        Icons.check_circle,
        color: AppColors.ok,
        size: 24,
      ),
      _RowState.active => const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
      _RowState.pending => CircleAvatar(
        radius: 12,
        backgroundColor: AppColors.soft,
        child: Text(
          '${index + 1}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ),
    };
    return Semantics(
      label:
          '$title(${switch (state) {
            _RowState.done => '完了',
            _RowState.failed => '失敗',
            _RowState.active => '処理中',
            _RowState.pending => 'これから',
          }})',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 28, child: Center(child: icon)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: state == _RowState.active
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: state == _RowState.pending
                      ? AppColors.muted
                      : AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 処理中の演出(イコライザー風のバー)。
class _Equalizer extends StatefulWidget {
  const _Equalizer();

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Container(
              width: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height:
                  14 +
                  46 *
                      (0.5 + 0.5 * sin(2 * pi * _controller.value + i * 1.37))
                          .abs(),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accent2],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}
