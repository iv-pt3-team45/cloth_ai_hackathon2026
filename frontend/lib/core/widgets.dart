// 画面をまたいで使う見た目の部品(参考 UI `tadasii/` の theme.dart から。spec 015)。

import 'package:flutter/material.dart';

import 'theme.dart';

/// 白い角丸カード(各セクションの外枠)。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.children,
    this.title,
    this.step,
    this.trailing,
  });

  final String? title;

  /// 見出しの前に出す番号(入力画面の ①②③)
  final int? step;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // ListTile などのタップの演出が見えるよう、背景は Material で塗る(影だけ外側の装飾)
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F1F1B24),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      if (step != null) ...[
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: AppColors.accent,
                          child: Text(
                            '$step',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          title!,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// 箇条書き。
class Bullets extends StatelessWidget {
  const Bullets(this.items, {super.key, this.style});

  final List<String> items;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('・', style: style),
                Expanded(child: Text(item, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 補足の小さい文字。
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13));
}

/// 小さなラベル(Chip は読み上げでチェックボックス扱いになるため、表示専用にはこれを使う)。
class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.color = Colors.white,
    this.textColor = AppColors.muted,
    this.bold = false,
  });

  final String text;
  final Color color;
  final Color textColor;
  final bool bold;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: textColor,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
    ),
  );
}

/// 値の一覧を Pill で並べる(空なら何も出さない)。
class PillWrap extends StatelessWidget {
  const PillWrap(this.values, {super.key});

  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final v in values) Pill(v, textColor: AppColors.text)],
    );
  }
}

/// 画面上部に出す案内・エラーの枠。
class MessageBox extends StatelessWidget {
  const MessageBox({super.key, required this.color, required this.children});

  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}

/// 薄い茶の角丸の枠(カードの中の補足のまとまり)。
class SoftBox extends StatelessWidget {
  const SoftBox({super.key, required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: margin,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.soft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

/// エラーの文字(茶色)。
class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: AppColors.ng));
}
