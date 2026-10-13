import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'culture_models.dart';
import 'culture_vibe.dart';

// カルチャー情報(spec 008)の項目の部品。要点のカードとポップアップ(spec 039)の両方で使う。

/// 項目の見出し(灰色の小さい文字)。
class CultureLabel extends StatelessWidget {
  const CultureLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: AppColors.muted, fontSize: 13),
    );
  }
}

/// 見出しと Pill の一覧(空なら何も出さない)。
class CultureChips extends StatelessWidget {
  const CultureChips({super.key, required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CultureLabel(label),
          const SizedBox(height: 4),
          PillWrap(values),
        ],
      ),
    );
  }
}

/// 「よく使う色」の一覧。辞書で色が分かるものは、Pill の左に色の丸を付ける(spec 039)。
class CultureColors extends StatelessWidget {
  const CultureColors({super.key, required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CultureLabel('よく使う色'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final v in values) _ColorPill(v)],
          ),
        ],
      ),
    );
  }
}

class _ColorPill extends StatelessWidget {
  const _ColorPill(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final color = CultureVibe.colorOf(name);
    if (color == null) return Pill(name, textColor: AppColors.text);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: ValueKey('color-dot-$name'),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}

/// 見出しと文章(空なら何も出さない)。
class CultureParagraph extends StatelessWidget {
  const CultureParagraph({super.key, required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [CultureLabel(label), SelectableText(text)],
      ),
    );
  }
}

/// 見出しと箇条書き(空なら何も出さない)。
class CultureBullets extends StatelessWidget {
  const CultureBullets({super.key, required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [CultureLabel(label), for (final v in values) Text('・$v')],
      ),
    );
  }
}

/// セクションの根拠になった出典番号(項目の近くに示す)。
class CultureCitations extends StatelessWidget {
  const CultureCitations({super.key, required this.indices});

  final List<int> indices;

  @override
  Widget build(BuildContext context) {
    if (indices.isEmpty) return const SizedBox.shrink();
    return Hint('出典: ${indices.map((i) => '[$i]').join(' ')}');
  }
}

/// この MV の衣装(シーンごと。MV の映像が根拠)。
class MvOutfitView extends StatelessWidget {
  const MvOutfitView({super.key, required this.outfit});

  final MvOutfit outfit;

  @override
  Widget build(BuildContext context) {
    final problem = mvOutfitProblem(outfit);
    if (problem != null) return Text(problem);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final look in outfit.looks) ...[
          if (look.label.isNotEmpty)
            Text(
              look.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          for (final item in look.items) Text('・${describeOutfitItem(item)}'),
          const SizedBox(height: 4),
        ],
        const Hint('根拠: MV の映像'),
      ],
    );
  }
}

/// MV の衣装を出せないときの理由(出せるなら null)。
String? mvOutfitProblem(MvOutfit outfit) {
  if (!outfit.isOk) {
    return outfit.message.isEmpty ? 'MV の映像を解析できませんでした' : outfit.message;
  }
  if (outfit.looks.isEmpty) return '映像から衣装を読み取れませんでした';
  return null;
}

/// 例: 「ワンピース(白・ピンク / ガーリー / ミニ丈) フリル」
String describeOutfitItem(OutfitItem item) {
  final details = [
    if (item.colors.isNotEmpty) item.colors.join('・'),
    if (item.style.isNotEmpty) item.style,
    if (item.shape.isNotEmpty) item.shape,
  ];
  final head = details.isEmpty
      ? item.category
      : '${item.category}(${details.join(' / ')})';
  return item.notes.isEmpty ? head : '$head ${item.notes}';
}
