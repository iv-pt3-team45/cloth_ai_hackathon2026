import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'photo_picker.dart';
import 'wardrobe_models.dart';
import 'wardrobe_repository.dart';
import 'wardrobe_review_screen.dart';

/// 入力の段階の「③ 手持ちの服」のカード(spec 010。見た目は spec 015)。
///
/// 登録済みの服を写真の格子で並べ、写真を追加して登録したり、不要になった服を削除したりできる。
/// 写真をタップすると属性(種類・色・素材など)を下から開くシートで見られる。
/// 一覧が変わるたびに [onChanged] で外へ渡す(提案のチェックリストと進捗の画面に使う)。
class WardrobeSection extends StatefulWidget {
  const WardrobeSection({
    super.key,
    this.repository,
    this.picker,
    this.onChanged,
  });

  final WardrobeRepository? repository;
  final PhotoPicker? picker;

  /// 登録済みの服の一覧が変わったときに呼ばれる(読み込み中・失敗は null)
  final ValueChanged<List<RegisteredCloth>?>? onChanged;

  @override
  State<WardrobeSection> createState() => _WardrobeSectionState();
}

class _WardrobeSectionState extends State<WardrobeSection> {
  late final WardrobeRepository _repository =
      widget.repository ?? WardrobeRepository();
  late final PhotoPicker _picker = widget.picker ?? ImagePickerPhotoPicker();
  List<RegisteredCloth>? _items;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _setItems(List<RegisteredCloth>? items) {
    setState(() => _items = items);
    widget.onChanged?.call(items);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repository.list();
      if (!mounted) return;
      _setItems(items);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.detail);
    } on Exception {
      if (!mounted) return;
      setState(() => _error = 'サーバーに接続できませんでした');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 写真を選び、確認画面で解析・保存する。保存したら一覧を読み直す。
  Future<void> _addPhotos() async {
    final picked = await _picker.pick(limit: maxPhotosPerBatch);
    if (picked.isEmpty || !mounted) return;

    var photos = picked;
    if (picked.length > maxPhotosPerBatch) {
      photos = picked.take(maxPhotosPerBatch).toList();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '一度に登録できるのは $maxPhotosPerBatch 枚までです。先頭の $maxPhotosPerBatch 枚を使います',
          ),
        ),
      );
    }

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            WardrobeReviewScreen(repository: _repository, photos: photos),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(RegisteredCloth item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この服を削除しますか？'),
        content: Text('「${item.attributes.category}」を手持ちの服から削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.delete(item.id);
      if (!mounted) return;
      _setItems(_items?.where((i) => i.id != item.id).toList());
      messenger.showSnackBar(const SnackBar(content: Text('削除しました')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.detail)));
    } on Exception {
      messenger.showSnackBar(const SnackBar(content: Text('サーバーに接続できませんでした')));
    }
  }

  /// 属性を下から開くシートで見せる(spec 010 AC-8 の「主な属性」)。
  void _showDetail(RegisteredCloth item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox.square(
                  dimension: 96,
                  child: ClothPhoto(url: _repository.imageUrl(item.image)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.attributes.category,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final line in describeAttributes(item.attributes))
                      Text(line, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SectionCard(
      step: 3,
      title: '手持ちの服',
      trailing: items == null
          ? null
          : Text(
              '${items.length} 点',
              style: const TextStyle(color: AppColors.muted),
            ),
      children: [
        const Hint(
          '服の写真を追加すると、AI が種類・色・素材などを読み取って登録します(1 回 $maxPhotosPerBatch 枚まで)。写真をタップすると読み取った内容を見られます。',
        ),
        const SizedBox(height: 12),
        ..._buildBody(items),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addPhotos,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('写真を選ぶ'),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildBody(List<RegisteredCloth>? items) {
    if (items == null) {
      if (_error != null && !_loading) {
        return [
          ErrorText(_error!),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _load, child: const Text('再読み込み')),
          ),
          const SizedBox(height: 8),
        ];
      }
      return const [LinearProgressIndicator(), SizedBox(height: 12)];
    }
    if (items.isEmpty) {
      return const [
        Hint('まだ服が登録されていません。「写真を選ぶ」から登録してください'),
        SizedBox(height: 12),
      ];
    }
    return [
      GridView.extent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final item in items)
            _ClothTile(
              key: ValueKey('cloth-${item.id}'),
              item: item,
              imageUrl: _repository.imageUrl(item.image),
              onTap: () => _showDetail(item),
              onDelete: () => _delete(item),
            ),
        ],
      ),
      const SizedBox(height: 12),
    ];
  }
}

/// 属性を画面に出す行(空の項目は出さない)。
List<String> describeAttributes(ClothAttributes a) {
  String join(List<String> values) => values.join('・');
  final details = [
    if (a.material.isNotEmpty) '素材: ${a.material}',
    if (a.shape.isNotEmpty) '形: ${a.shape}',
    if (a.pattern.isNotEmpty) '柄: ${a.pattern}',
  ];
  final wearing = [
    if (a.seasons.isNotEmpty) '季節: ${join(a.seasons)}',
    if (a.warmth != null) '暖かさ: ${a.warmth}',
  ];
  return [
    if (a.colors.isNotEmpty) '色: ${join(a.colors)}',
    if (details.isNotEmpty) details.join(' / '),
    if (a.style.isNotEmpty) '系統: ${a.style}',
    if (wearing.isNotEmpty) wearing.join(' / '),
    if (a.occasions.isNotEmpty)
      '場面: ${join(a.occasions.map(occasionLabel).toList())}',
    if (a.notes.isNotEmpty) a.notes,
  ];
}

/// 登録済みの服の写真(読み込めない場合はアイコンを出す)。
class ClothPhoto extends StatelessWidget {
  const ClothPhoto({super.key, required this.url});

  /// 空文字ならプレースホルダを出す
  final String url;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: AppColors.soft,
      child: Center(child: Icon(Icons.checkroom, color: AppColors.muted)),
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

/// 格子の 1 マス(写真・種類のラベル・削除ボタン)。
class _ClothTile extends StatelessWidget {
  const _ClothTile({
    super.key,
    required this.item,
    required this.imageUrl,
    required this.onTap,
    required this.onDelete,
  });

  final RegisteredCloth item;
  final String imageUrl;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: AppColors.soft,
            child: InkWell(
              onTap: onTap,
              child: Ink(child: ClothPhoto(url: imageUrl)),
            ),
          ),
        ),
        Positioned(
          left: 4,
          bottom: 4,
          right: 32,
          child: IgnorePointer(child: _Badge(item.attributes.category)),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: IconButton(
            tooltip: '削除',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
            ),
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    ),
  );
}
