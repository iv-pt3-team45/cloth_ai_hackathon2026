import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'photo_picker.dart';
import 'wardrobe_models.dart';
import 'wardrobe_repository.dart';
import 'wardrobe_review_screen.dart';

/// 手持ちの服(spec 010)の一覧。写真を追加して登録し、不要になった服を削除できる。
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key, this.repository, this.picker});

  final WardrobeRepository? repository;
  final PhotoPicker? picker;

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repository.list();
      if (!mounted) return;
      setState(() => _items = items);
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
      setState(() => _items = _items?.where((i) => i.id != item.id).toList());
      messenger.showSnackBar(const SnackBar(content: Text('削除しました')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.detail)));
    } on Exception {
      messenger.showSnackBar(const SnackBar(content: Text('サーバーに接続できませんでした')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手持ちの服'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPhotos,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('写真を追加'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final items = _items;
    if (items == null) {
      if (_error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 8),
              FilledButton.tonal(onPressed: _load, child: const Text('再読み込み')),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('まだ服が登録されていません。右下の「写真を追加」から登録してください'),
        ),
      );
    }

    return ListView.builder(
      // 右下のボタンと重ならないよう下に余白を取る
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ClothCard(
          item: item,
          imageUrl: _repository.imageUrl(item.image),
          onDelete: () => _delete(item),
        );
      },
    );
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

class _ClothCard extends StatelessWidget {
  const _ClothCard({
    required this.item,
    required this.imageUrl,
    required this.onDelete,
  });

  final RegisteredCloth item;
  final String imageUrl;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.checkroom)),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 96,
                child: imageUrl.isEmpty
                    ? placeholder
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        // Flutter Web(CanvasKit)で読み込めない場合は <img> 要素で表示させる
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        errorBuilder: (context, error, stackTrace) =>
                            placeholder,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.attributes.category,
                    style: theme.textTheme.titleMedium,
                  ),
                  for (final line in describeAttributes(item.attributes))
                    Text(line, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: '削除',
            ),
          ],
        ),
      ),
    );
  }
}
