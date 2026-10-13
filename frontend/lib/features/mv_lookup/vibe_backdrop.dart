import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'culture_vibe.dart';

/// カードの後ろで流し続ける背景の動き(spec 039 D)。
///
/// [effect] が null、または [animate] が false(動きを減らす設定)のときは何も描かず、アニメーションも止める。
/// 粒は数十個に抑え、`RepaintBoundary` でカードの再描画と切り離す(Web のスマホで重くしないため)。
class VibeBackdrop extends StatefulWidget {
  const VibeBackdrop({
    super.key,
    required this.effect,
    required this.colors,
    this.animate = true,
  });

  final VibeEffect? effect;

  /// 粒の色(差し色 2 つ)
  final List<Color> colors;
  final bool animate;

  /// 背景が実際に動いているか
  bool get running => effect != null && animate;

  @override
  State<VibeBackdrop> createState() => _VibeBackdropState();
}

class _VibeBackdropState extends State<VibeBackdrop>
    with SingleTickerProviderStateMixin {
  /// 10 秒で 1 周。粒の位置はこの値から計算する(状態を毎フレーム持たない)
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(VibeBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.running) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effect = widget.effect;
    if (effect == null || !widget.animate) return const SizedBox.expand();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _VibePainter(
            effect: effect,
            colors: widget.colors,
            progress: _controller,
          ),
        ),
      ),
    );
  }
}

/// 粒 1 つの初期値(演出ごとに固定の乱数の種で作る)。
class _Particle {
  _Particle(Random random)
    : x = random.nextDouble(),
      y = random.nextDouble(),
      phase = random.nextDouble(),
      speed = 0.6 + random.nextDouble() * 0.8,
      size = random.nextDouble(),
      colorIndex = random.nextInt(3),
      shape = random.nextInt(2);

  final double x;
  final double y;
  final double phase;
  final double speed;
  final double size;
  final int colorIndex;
  final int shape;
}

/// 演出ごとの粒の数(design §5.5)
const _counts = {
  VibeEffect.sparkle: 28,
  VibeEffect.sparks: 32,
  VibeEffect.petals: 22,
  VibeEffect.neon: 24,
};

final _particles = {
  for (final effect in VibeEffect.values) effect: _generate(effect),
};

List<_Particle> _generate(VibeEffect effect) {
  final random = Random(effect.index + 38);
  return List.generate(
    _counts[effect]!,
    (_) => _Particle(random),
    growable: false,
  );
}

class _VibePainter extends CustomPainter {
  _VibePainter({
    required this.effect,
    required this.colors,
    required this.progress,
  }) : super(repaint: progress);

  final VibeEffect effect;
  final List<Color> colors;
  final Animation<double> progress;

  /// 粒の色(差し色 2 つと、その明るい色)
  Color _color(int index) {
    final base = colors[index % colors.length];
    return index == 2 ? Color.lerp(base, Colors.white, 0.6)! : base;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    switch (effect) {
      case VibeEffect.sparkle:
        _paintSparkle(canvas, size, t);
      case VibeEffect.sparks:
        _paintSparks(canvas, size, t);
      case VibeEffect.petals:
        _paintPetals(canvas, size, t);
      case VibeEffect.neon:
        _paintNeon(canvas, size, t);
    }
  }

  /// 星とハートが、左右に揺れながら下から上へ舞い上がる
  void _paintSparkle(Canvas canvas, Size size, double t) {
    for (final p in _particles[effect]!) {
      final f = (p.phase + t * p.speed * 2) % 1;
      final x = (p.x + sin(2 * pi * (f * 2 + p.phase)) * 0.03) * size.width;
      final y = (1.1 - f * 1.2) * size.height;
      final r = 5 + p.size * 7;
      final paint = Paint()
        ..color = _color(p.colorIndex).withValues(alpha: 0.7 * sin(pi * f));
      canvas.drawPath(
        p.shape == 0 ? _star(Offset(x, y), r) : _heart(Offset(x, y), r),
        paint,
      );
    }
  }

  /// 火花が下から速く上がり、上部の照明 2 つが明滅する
  void _paintSparks(Canvas canvas, Size size, double t) {
    for (var i = 0; i < 2; i++) {
      final center = Offset(size.width * (0.25 + i * 0.5), 0);
      final radius = size.shortestSide * 0.7;
      final alpha = 0.18 + 0.14 * sin(2 * pi * (t * 6 + i * 0.5));
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _color(i).withValues(alpha: alpha),
              _color(i).withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    for (final p in _particles[effect]!) {
      final f = (p.phase + t * p.speed * 4) % 1;
      final x = (p.x + sin(2 * pi * (f + p.phase)) * 0.015) * size.width;
      final y = (1.05 - f * 1.1) * size.height;
      canvas.drawCircle(
        Offset(x, y),
        1.5 + p.size * 2,
        Paint()
          ..color = _color(
            p.colorIndex == 0 ? 2 : p.colorIndex,
          ).withValues(alpha: 0.9 * (1 - f))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  /// 花びらが回転しながら、上からゆっくり舞い落ちる
  void _paintPetals(Canvas canvas, Size size, double t) {
    for (final p in _particles[effect]!) {
      final f = (p.phase + t * p.speed) % 1;
      final x = (p.x + sin(2 * pi * (f + p.phase)) * 0.06) * size.width;
      final y = (-0.1 + f * 1.2) * size.height;
      final w = 8 + p.size * 6;
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(2 * pi * (f * p.speed + p.phase))
        ..drawOval(
          Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.6),
          Paint()..color = _color(p.colorIndex).withValues(alpha: 0.55),
        )
        ..restore();
    }
  }

  /// 光の粒が線を描いて斜めに流れる
  void _paintNeon(Canvas canvas, Size size, double t) {
    for (final p in _particles[effect]!) {
      final f = (p.phase + t * p.speed * 2) % 1;
      final start = Offset(
        (-0.2 + f * 1.4) * size.width,
        (p.y + f * 0.3) * size.height,
      );
      final length = 30 + p.size * 40;
      final paint = Paint()
        ..color = _color(p.colorIndex).withValues(alpha: 0.8 * sin(pi * f))
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawLine(start, start - Offset(length, length * 0.2), paint);
    }
  }

  static Path _star(Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? r : r * 0.35;
      final angle = pi / 4 * i - pi / 2;
      final point = c + Offset(cos(angle) * radius, sin(angle) * radius);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  static Path _heart(Offset c, double r) {
    return Path()
      ..moveTo(c.dx, c.dy + r * 0.9)
      ..cubicTo(
        c.dx - r * 1.4,
        c.dy - r * 0.1,
        c.dx - r * 0.6,
        c.dy - r * 1.1,
        c.dx,
        c.dy - r * 0.35,
      )
      ..cubicTo(
        c.dx + r * 0.6,
        c.dy - r * 1.1,
        c.dx + r * 1.4,
        c.dy - r * 0.1,
        c.dx,
        c.dy + r * 0.9,
      )
      ..close();
  }

  @override
  bool shouldRepaint(_VibePainter oldDelegate) =>
      oldDelegate.effect != effect || !listEquals(oldDelegate.colors, colors);
}

/// カルチャー情報が届いたときに 1 回だけ出す、切り替わりの演出(spec 039 D)。
///
/// [origin] のウィジェットの中心から、[color] の円が画面いっぱいに広がりながら消える。
/// 画面の操作は妨げない(`IgnorePointer`)。
void showVibeBurst(
  BuildContext context, {
  GlobalKey? origin,
  required Color color,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final box = origin?.currentContext?.findRenderObject() as RenderBox?;
  final center = box != null && box.hasSize
      ? box.localToGlobal(box.size.center(Offset.zero))
      : null;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => VibeBurst(
      center: center,
      color: color,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

/// 切り替わりの演出の本体(700ms で広がって消え、[onDone] を呼ぶ)。
class VibeBurst extends StatefulWidget {
  const VibeBurst({
    super.key,
    required this.color,
    required this.onDone,
    this.center,
  });

  /// 始点(null なら画面の中央)
  final Offset? center;
  final Color color;
  final VoidCallback onDone;

  @override
  State<VibeBurst> createState() => _VibeBurstState();
}

class _VibeBurstState extends State<VibeBurst>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _BurstPainter(
            center: widget.center,
            color: widget.color,
            t: _controller.value,
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.center, required this.color, required this.t});

  final Offset? center;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = center ?? size.center(Offset.zero);
    // 画面の端まで届く半径
    final reach = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - c).distance).reduce(max);
    final grow = Curves.easeOutCubic.transform((t / 0.6).clamp(0, 1));
    final fade = t < 0.5 ? 1.0 : 1 - (t - 0.5) / 0.5;
    canvas.drawCircle(
      c,
      reach * grow,
      Paint()..color = color.withValues(alpha: 0.55 * fade),
    );
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) => oldDelegate.t != t;
}
