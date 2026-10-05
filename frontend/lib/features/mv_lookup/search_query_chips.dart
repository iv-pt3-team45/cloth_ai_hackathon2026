import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 実行された Google 検索のクエリを並べる。
///
/// 検索候補の HTML を描画できない(Web 以外)・HTML が返らなかった場合の代わりに使う。
class SearchQueryChips extends StatelessWidget {
  const SearchQueryChips({super.key, required this.queries});

  final List<String> queries;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final query in queries)
          Chip(
            avatar: const Icon(Icons.search, size: 16, color: AppColors.muted),
            label: Text(query),
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.border),
            shape: const StadiumBorder(),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
