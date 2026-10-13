import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'photo_picker.dart';
import 'wardrobe_models.dart';
import 'wardrobe_repository.dart';

/// 選んだ写真を 1 枚ずつ解析し、保存前に確認・修正する画面(spec 010)。
///
/// 保存するまでサーバには何も残らない(解析は保存しない)。
/// 閉じるときは、1 枚でも保存したかどうかを返す(一覧を読み直すため)。
class WardrobeReviewScreen extends StatefulWidget {
  const WardrobeReviewScreen({
    super.key,
    required this.repository,
    required this.photos,
  });

  final WardrobeRepository repository;
  final List<PickedPhoto> photos;

  @override
  State<WardrobeReviewScreen> createState() => _WardrobeReviewScreenState();
}

enum _Status { waiting, analyzing, done, failed }

/// 写真 1 枚ぶんの確認中の状態。
class _PhotoDraft {
  _PhotoDraft(this.photo);

  final PickedPhoto photo;
  _Status status = _Status.waiting;
  String? error;

  /// 再解析で直る見込みがあるか(形式やサイズの誤りは直らない)
  bool retryable = true;
  bool included = true;
  bool saved = false;
  String summary = '';
  List<_ItemDraft> items = [];
}

/// 服 1 点ぶんの確認中の状態。
class _ItemDraft {
  _ItemDraft(this.attributes);

  ClothAttributes attributes;
  bool included = true;
}

class _WardrobeReviewScreenState extends State<WardrobeReviewScreen> {
  late final List<_PhotoDraft> _drafts = [
    for (final photo in widget.photos) _PhotoDraft(photo),
  ];
  bool _saving = false;
  bool _savedAny = false;
  String? _saveError;

  bool get _analyzing => _drafts.any((d) => d.status == _Status.analyzing);
  bool get _busy => _analyzing || _saving;

  /// 保存の対象(登録する写真の、登録する服)
  Iterable<(_PhotoDraft, List<_ItemDraft>)> get _targets sync* {
    for (final draft in _drafts) {
      if (draft.saved || !draft.included || draft.status != _Status.done) {
        continue;
      }
      final items = draft.items.where((i) => i.included).toList();
      if (items.isNotEmpty) yield (draft, items);
    }
  }

  int get _targetCount => _targets.fold(0, (sum, t) => sum + t.$2.length);

  bool get _hasEmptyCategory => _targets.any(
    (t) => t.$2.any((item) => item.attributes.category.trim().isEmpty),
  );

  @override
  void initState() {
    super.initState();
    for (final draft in _drafts) {
      if (!draft.photo.isSupported) {
        // 形式が対応外の写真は API を呼ばずにエラーにする(AC-11)
        draft
          ..status = _Status.failed
          ..retryable = false
          ..error = '対応していない形式です。jpg / png / webp の写真を選んでください';
      }
    }
    _analyzeAll();
  }

  /// 1 枚ずつ順に解析する(同時に呼ばない。クォータの瞬間的な消費を避けるため)。
  Future<void> _analyzeAll() async {
    for (final draft in _drafts) {
      if (!mounted) return;
      if (draft.status == _Status.waiting) await _analyze(draft);
    }
  }

  Future<void> _analyze(_PhotoDraft draft) async {
    setState(() {
      draft
        ..status = _Status.analyzing
        ..error = null;
    });
    try {
      final result = await widget.repository.analyze(draft.photo);
      if (!mounted) return;
      setState(() {
        if (result.items.isEmpty) {
          draft
            ..status = _Status.failed
            ..error = '服が写っていないようです。別の写真を選ぶか、再解析してください';
        } else {
          draft
            ..status = _Status.done
            ..summary = result.summary
            ..items = [for (final item in result.items) _ItemDraft(item)];
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        draft
          ..status = _Status.failed
          ..error = e.detail
          // 形式・サイズの誤り(400 / 413 / 422)は再解析しても直らない
          ..retryable = !const {400, 413, 422}.contains(e.statusCode);
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        draft
          ..status = _Status.failed
          ..error = 'サーバーに接続できませんでした';
      });
    }
  }

  /// 写真ごとに順に保存する。途中で失敗したら、保存できた写真を外して残りを表示する。
  Future<void> _save() async {
    if (_busy || _targetCount == 0 || _hasEmptyCategory) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });

    for (final (draft, items) in _targets.toList()) {
      try {
        await widget.repository.register(draft.photo, [
          for (final item in items) item.attributes,
        ], summary: draft.summary);
        _savedAny = true;
        draft.saved = true;
      } on ApiException catch (e) {
        _saveError = '「${draft.photo.name}」を保存できませんでした: ${e.detail}';
        break;
      } on Exception {
        _saveError = '「${draft.photo.name}」を保存できませんでした: サーバーに接続できませんでした';
        break;
      }
    }
    if (!mounted) return;
    if (_saveError == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _saving = false);
  }

  /// 保存せずに戻る。解析結果があれば確認する(AC-7)。
  Future<void> _leave() async {
    if (_saving) return;
    final hasResults = _drafts.any((d) => !d.saved && d.status == _Status.done);
    if (hasResults) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('保存せずに戻りますか？'),
          content: const Text('保存していない解析結果は破棄されます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('確認を続ける'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存せずに戻る'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.of(context).pop(_savedAny);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final visible = _drafts.where((d) => !d.saved).toList();
    final analyzingIndex = _drafts.indexWhere(
      (d) => d.status == _Status.analyzing,
    );
    final count = _targetCount;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      // 背景は入力の画面と同じ配色のグラデーション。カードの外の文字は onBackground(spec 041)
      child: PaletteBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: palette.onBackground,
            title: Text('写真の確認', style: TextStyle(color: palette.onBackground)),
            leading: IconButton(
              onPressed: _saving ? null : _leave,
              icon: const Icon(Icons.close),
              color: palette.onBackground,
              tooltip: 'キャンセル',
            ),
          ),
          body: Column(
            children: [
              if (analyzingIndex >= 0) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '解析中 ${analyzingIndex + 1} / ${_drafts.length}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: palette.onBackground,
                    ),
                  ),
                ),
                const LinearProgressIndicator(),
              ],
              if (_saveError != null)
                MaterialBanner(
                  content: Text(_saveError!),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _saveError = null),
                      child: const Text('閉じる'),
                    ),
                  ],
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final draft in visible)
                      _PhotoCard(
                        key: ObjectKey(draft),
                        draft: draft,
                        busy: _busy,
                        onRetry: () => _analyze(draft),
                        onChanged: () => setState(() {}),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // 画面下に固定する保存のバー(入力の段階の送信バーと同じ見た目。spec 015)
          bottomNavigationBar: Material(
            elevation: 8,
            color: Colors.white,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_hasEmptyCategory)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '種類が空の服があります。種類を入力してください',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy || count == 0 || _hasEmptyCategory
                            ? null
                            : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(count == 0 ? '保存する服がありません' : '$count 点を保存'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    super.key,
    required this.draft,
    required this.busy,
    required this.onRetry,
    required this.onChanged,
  });

  final _PhotoDraft draft;
  final bool busy;
  final VoidCallback onRetry;

  /// 状態を書き換えたことを親に伝える(保存ボタンの状態を更新するため)
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = switch (draft.status) {
      _Status.waiting => '解析待ち',
      _Status.analyzing => '解析中…',
      _Status.done => '服 ${draft.items.length} 点',
      _Status.failed => 'エラー',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    draft.photo.bytes,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => SizedBox(
                      width: 120,
                      height: 120,
                      child: ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(child: Icon(Icons.image)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(draft.photo.name, style: theme.textTheme.titleSmall),
                      Text(status),
                      if (draft.error != null)
                        Text(
                          draft.error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      if (draft.status == _Status.failed && draft.retryable)
                        OutlinedButton.icon(
                          onPressed: busy ? null : onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('再解析'),
                        ),
                      if (draft.summary.isNotEmpty)
                        Text(draft.summary, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (draft.status == _Status.done)
                  Column(
                    children: [
                      Switch(
                        value: draft.included,
                        onChanged: busy
                            ? null
                            : (value) {
                                draft.included = value;
                                onChanged();
                              },
                      ),
                      const Text('この写真を登録'),
                    ],
                  ),
              ],
            ),
            if (draft.status == _Status.done && draft.included)
              for (final (index, item) in draft.items.indexed)
                _ItemEditor(
                  key: ObjectKey(item),
                  number: index + 1,
                  item: item,
                  enabled: !busy,
                  onChanged: onChanged,
                ),
          ],
        ),
      ),
    );
  }
}

/// 服 1 点の属性の編集欄(AC-4)。
class _ItemEditor extends StatelessWidget {
  const _ItemEditor({
    super.key,
    required this.number,
    required this.item,
    required this.enabled,
    required this.onChanged,
  });

  final int number;
  final _ItemDraft item;
  final bool enabled;
  final VoidCallback onChanged;

  void _update(ClothAttributes Function(ClothAttributes a) change) {
    item.attributes = change(item.attributes);
    onChanged();
  }

  List<String> _toggle(List<String> values, String value, bool selected) {
    final set = {...values};
    selected ? set.add(value) : set.remove(value);
    return set.toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = item.attributes;

    Widget field(
      String label,
      String initial,
      ClothAttributes Function(ClothAttributes a, String v) apply, {
      double width = 200,
    }) => SizedBox(
      width: width,
      child: TextFormField(
        initialValue: initial,
        enabled: enabled && item.included,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) => _update((a) => apply(a, value)),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: item.included,
                onChanged: enabled
                    ? (value) {
                        item.included = value ?? false;
                        onChanged();
                      }
                    : null,
              ),
              Text('服 $number を登録する', style: theme.textTheme.titleSmall),
            ],
          ),
          if (item.included) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                field('種類', a.category, (a, v) => a.copyWith(category: v)),
                field(
                  '色(「、」区切り)',
                  a.colors.join('、'),
                  (a, v) => a.copyWith(
                    colors: v
                        .split(RegExp('[、,，]'))
                        .map((c) => c.trim())
                        .where((c) => c.isNotEmpty)
                        .toList(),
                  ),
                ),
                field('素材', a.material, (a, v) => a.copyWith(material: v)),
                field('形', a.shape, (a, v) => a.copyWith(shape: v)),
                field('柄', a.pattern, (a, v) => a.copyWith(pattern: v)),
                field('系統', a.style, (a, v) => a.copyWith(style: v)),
                field(
                  '特徴',
                  a.notes,
                  (a, v) => a.copyWith(notes: v),
                  width: 416,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ChoiceRow(
              label: '季節',
              children: [
                for (final season in seasonChoices)
                  FilterChip(
                    label: Text(season),
                    selected: a.seasons.contains(season),
                    onSelected: enabled
                        ? (selected) => _update(
                            (a) => a.copyWith(
                              seasons: seasonChoices
                                  .where(
                                    _toggle(
                                      a.seasons,
                                      season,
                                      selected,
                                    ).contains,
                                  )
                                  .toList(),
                            ),
                          )
                        : null,
                  ),
              ],
            ),
            _ChoiceRow(
              label: '暖かさ',
              children: [
                for (final warmth in warmthChoices)
                  ChoiceChip(
                    label: Text(warmth),
                    selected: a.warmth == warmth,
                    // もう一度押すと解除する(分からない場合)
                    onSelected: enabled
                        ? (selected) => _update(
                            (a) => a.copyWith(warmth: selected ? warmth : null),
                          )
                        : null,
                  ),
              ],
            ),
            _ChoiceRow(
              label: '使う場面',
              children: [
                for (final occasion in occasionChoices)
                  FilterChip(
                    label: Text(occasionLabel(occasion)),
                    selected: a.occasions.contains(occasion),
                    onSelected: enabled
                        ? (selected) => _update(
                            (a) => a.copyWith(
                              occasions: occasionChoices
                                  .where(
                                    _toggle(
                                      a.occasions,
                                      occasion,
                                      selected,
                                    ).contains,
                                  )
                                  .toList(),
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
          Expanded(child: Wrap(spacing: 6, runSpacing: 4, children: children)),
        ],
      ),
    );
  }
}
