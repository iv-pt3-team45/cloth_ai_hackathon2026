import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../mv_lookup/culture_models.dart';
import '../mv_lookup/grounding_footer.dart';
import '../mv_lookup/live_models.dart';
import '../mv_lookup/utils.dart';
import '../wardrobe/wardrobe_section.dart';
import 'outfit_models.dart';
import 'save_image.dart';

/// 「3 提案」の画面(参考 UI の result_view.dart を今のデータに合わせたもの。spec 015)。
///
/// コーデ名・着せた画像(拡大 / 保存)・使う服・選んだ理由・提案に使った情報を出す。
class OutfitResultView extends StatelessWidget {
  const OutfitResultView({
    super.key,
    required this.suggestion,
    required this.imageUrl,
    required this.onRetryImage,
    required this.onRestart,
    this.image,
    this.imageError,
    this.retryingImage = false,
    this.live,
    this.liveResult,
    this.culture,
    this.canSave = canSaveImage,
  });

  final OutfitSuggestion suggestion;
  final OutfitImage? image;
  final String? imageError;
  final bool retryingImage;

  /// 提案に使った情報(結果の画面で見返せるように出す)
  final LiveCandidate? live;
  final LiveSearchResult? liveResult;
  final CultureReport? culture;

  final String Function(String image) imageUrl;
  final VoidCallback onRetryImage;
  final VoidCallback onRestart;

  /// 「画像を保存」を出すか(Web のみ。テストで差し替える)
  final bool canSave;

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme;
    final live = this.live;
    final eventLine = live == null
        ? ''
        : [
            if (live.liveName.isNotEmpty) live.liveName,
            if (live.date != null) formatDate(live.date!),
            if (live.venue.isNotEmpty) live.venue,
          ].join(' ・ ');

    final hero = SectionCard(
      children: [
        if (eventLine.isNotEmpty)
          Text(eventLine, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(
          suggestion.title.isEmpty ? 'コーディネート提案' : suggestion.title,
          style: heading.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _imageArea(context),
        const SizedBox(height: 12),
        Text(
          '使うアイテム',
          style: heading.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (final item in suggestion.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox.square(
                    dimension: 52,
                    child: ClothPhoto(url: imageUrl(item.cloth.image)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.role.isNotEmpty)
                        Text(
                          item.role,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      Text(
                        item.cloth.attributes.category,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (item.reason.isNotEmpty) Text(item.reason),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (suggestion.excludedCount > 0)
          Hint('手持ちに無い服 ${suggestion.excludedCount} 点は提案から除きました'),
      ],
    );

    final reason = SectionCard(
      title: 'このコーデを選んだ理由',
      children: [
        if (suggestion.summary.isNotEmpty) Text(suggestion.summary),
        if (suggestion.points.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('ポイント', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Bullets(suggestion.points),
        ],
      ],
    );

    final details = [?_cultureCard(), ?_liveCard()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hero,
        reason,
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 640 || details.length < 2) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: details,
              );
            }
            // 広い画面では 2 列に並べる
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details[0]),
                const SizedBox(width: 16),
                Expanded(child: details[1]),
              ],
            );
          },
        ),
        Center(
          child: OutlinedButton(
            onPressed: onRestart,
            child: const Text('条件を変えてもう一度'),
          ),
        ),
      ],
    );
  }

  /// 着せた画像の欄(作り直し中 / 失敗 / 画像)。
  Widget _imageArea(BuildContext context) {
    if (retryingImage) {
      return const SoftBox(
        child: Row(
          children: [
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('マネキンに着せた画像を作っています(数十秒かかることがあります)')),
          ],
        ),
      );
    }
    final error = imageError;
    if (error != null) {
      return SoftBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '画像を作れませんでした',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ErrorText(error),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetryImage,
              icon: const Icon(Icons.refresh),
              label: const Text('画像を作り直す'),
            ),
          ],
        ),
      );
    }
    final image = this.image;
    if (image == null) {
      return const SoftBox(child: Hint('画像はまだありません'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _zoom(context, image.bytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              image.bytes,
              key: const ValueKey('outfit-image'),
              fit: BoxFit.contain,
              semanticLabel: '提案コーディネートを着せたマネキンの画像',
              errorBuilder: (context, error, stackTrace) =>
                  const SoftBox(child: Hint('画像を表示できませんでした')),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => _zoom(context, image.bytes),
              icon: const Icon(Icons.zoom_in),
              label: const Text('拡大して見る'),
            ),
            if (canSave)
              TextButton.icon(
                onPressed: () => saveImage(
                  image.bytes,
                  image.mimeType,
                  image.fileName.isEmpty
                      ? 'live-outfit.${image.mimeType.split('/').last}'
                      : image.fileName,
                ),
                icon: const Icon(Icons.download),
                label: const Text('画像を保存'),
              ),
          ],
        ),
      ],
    );
  }

  /// MV のファッション(カルチャー情報。グラウンディングの結果なので出典と検索候補を添える)。
  Widget? _cultureCard() {
    final culture = this.culture;
    if (culture == null || !culture.identified) return null;
    final fashion = culture.fashion;
    final outfit = culture.mvOutfit;
    return SectionCard(
      title: 'MV のファッション',
      children: [
        PillWrap([...fashion.styles, ...fashion.colors, ...fashion.items]),
        if (fashion.worldview.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('世界観: ${fashion.worldview}'),
        ],
        if (outfit.isOk && outfit.looks.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'この MV の衣装',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Bullets([for (final look in outfit.looks) _describeLook(look)]),
        ],
        if (culture.background.genres.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('音楽ジャンル', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          PillWrap(culture.background.genres),
        ],
        GroundingFooter(
          sources: culture.sources,
          searchSuggestionsHtml: culture.searchSuggestionsHtml,
          webSearchQueries: culture.webSearchQueries,
        ),
      ],
    );
  }

  /// 会場・天気(選んだライブ。グラウンディングの結果なので出典と検索候補を添える)。
  Widget? _liveCard() {
    final live = this.live;
    if (live == null) return null;
    final date = live.date;
    final location = live.location.isEmpty ? '' : '(${live.location})';
    final result = liveResult;
    return SectionCard(
      title: '会場・天気',
      children: [
        Text(
          live.liveName.isEmpty ? '(ライブ名不明)' : live.liveName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text('場所: ${live.venue.isEmpty ? '不明' : live.venue}$location'),
        Text('日付: ${date == null ? '不明' : formatDate(date)}'),
        Text('天気: ${live.weather.description}'),
        if (result != null)
          GroundingFooter(
            sources: result.sources,
            searchSuggestionsHtml: result.searchSuggestionsHtml,
            webSearchQueries: result.webSearchQueries,
          ),
      ],
    );
  }

  static String _describeLook(OutfitLook look) {
    final items = look.items
        .map(
          (i) => i.colors.isEmpty
              ? i.category
              : '${i.category}(${i.colors.join('・')})',
        )
        .join('、');
    return look.label.isEmpty ? items : '${look.label}: $items';
  }

  void _zoom(BuildContext context, Uint8List image) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image.memory(
                  image,
                  key: const ValueKey('outfit-image-zoom'),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: SafeArea(
                child: IconButton(
                  tooltip: '閉じる',
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
