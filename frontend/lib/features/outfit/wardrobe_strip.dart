import 'package:flutter/material.dart';

import '../wardrobe/wardrobe_models.dart';

/// 1 画面に並ぶ枚数(spec 011 design 5.3)。残りは横にスクロールして見る。
int itemsPerScreen(double width) {
  if (width < 600) return 4;
  if (width < 1024) return 6;
  return 8;
}

/// 手持ちの服を小さな写真で横に並べる(横スクロール)。
///
/// 1 枚の幅は、画面の幅に 1 画面ぶんの枚数がちょうど収まるように決める。
class WardrobeStrip extends StatelessWidget {
  const WardrobeStrip({super.key, required this.items, required this.imageUrl});

  static const gap = 8.0;

  final List<RegisteredCloth> items;

  /// 写真のファイル名から URL を作る(空文字ならプレースホルダを出す)
  final String Function(String image) imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final perScreen = itemsPerScreen(constraints.maxWidth);
        final size = (constraints.maxWidth - gap * (perScreen - 1)) / perScreen;
        return SizedBox(
          height: size + 24,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: gap),
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                key: ValueKey('strip-${item.id}'),
                width: size,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox.square(
                        dimension: size,
                        child: _Photo(url: imageUrl(item.image)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.attributes.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.checkroom)),
    );
    if (url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.cover,
      // Flutter Web(CanvasKit)で読み込めない場合は <img> 要素で表示させる
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}
