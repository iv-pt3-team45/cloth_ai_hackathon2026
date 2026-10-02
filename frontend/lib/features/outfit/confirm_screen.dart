import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../mv_lookup/culture_models.dart';
import '../mv_lookup/grounding_footer.dart';
import '../mv_lookup/mv_lookup_snapshot.dart';
import '../mv_lookup/utils.dart';
import '../wardrobe/wardrobe_models.dart';
import '../wardrobe/wardrobe_repository.dart';
import 'outfit_models.dart';
import 'outfit_repository.dart';
import 'wardrobe_strip.dart';

/// 情報の確認タブ(spec 011)。
///
/// 他のタブで入力・取得した情報を表示専用でまとめ、そろったら手持ちの服からコーデを提案する。
/// MV 検索タブの状態は [snapshot] で受け取り、手持ちの服は表示されたとき([active])に読み直す。
class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({
    super.key,
    required this.snapshot,
    this.active = true,
    this.wardrobeRepository,
    this.outfitRepository,
  });

  final ValueListenable<MvLookupSnapshot> snapshot;

  /// 確認タブが表示中か(表示されたときに手持ちの服を読み直す)
  final bool active;
  final WardrobeRepository? wardrobeRepository;
  final OutfitRepository? outfitRepository;

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  late final WardrobeRepository _wardrobe =
      widget.wardrobeRepository ?? WardrobeRepository();
  late final OutfitRepository _outfit =
      widget.outfitRepository ?? OutfitRepository();

  List<RegisteredCloth>? _clothes;
  String? _clothesError;

  bool _suggesting = false;
  OutfitSuggestion? _suggestion;
  String? _suggestError;

  bool _imaging = false;
  OutfitImage? _image;
  String? _imageError;

  bool get _busy => _suggesting || _imaging;

  @override
  void initState() {
    super.initState();
    _loadClothes();
  }

  @override
  void didUpdateWidget(ConfirmScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 手持ちの服タブで登録・削除した内容を反映する
    if (widget.active && !oldWidget.active) _loadClothes();
  }

  Future<void> _loadClothes() async {
    setState(() => _clothesError = null);
    try {
      final clothes = await _wardrobe.list();
      if (!mounted) return;
      setState(() => _clothes = clothes);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _clothesError = e.detail);
    } on Exception {
      if (!mounted) return;
      setState(() => _clothesError = 'サーバーに接続できませんでした');
    }
  }

  /// 提案に足りないもの(AC-8)
  List<String> _missing(MvLookupSnapshot s) => [
    if (_clothes?.isEmpty ?? true) '手持ちの服',
    if (s.video == null) 'MV',
    if (s.selectedLive == null) 'ライブの選択',
  ];

  /// ① 提案 → ② 画像の生成 を続けて行う。押し直すと前の結果を消してやり直す(AC-14)。
  Future<void> _suggest(MvLookupSnapshot s) async {
    final video = s.video;
    final live = s.selectedLive;
    if (_busy || video == null || live == null) return;
    setState(() {
      _suggesting = true;
      _suggestion = null;
      _suggestError = null;
      _image = null;
      _imageError = null;
    });
    try {
      final suggestion = await _outfit.suggest(
        video: video,
        live: live,
        culture: s.culture,
      );
      if (!mounted) return;
      setState(() => _suggestion = suggestion);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _suggestError = e.detail);
    } on Exception {
      if (!mounted) return;
      setState(() => _suggestError = 'サーバーに接続できませんでした');
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
    if (_suggestion != null && mounted) await _generateImage();
  }

  /// 提案の服をマネキンに着せた画像を生成する。失敗しても提案は残す(AC-13)。
  Future<void> _generateImage() async {
    final suggestion = _suggestion;
    if (suggestion == null || _imaging) return;
    setState(() {
      _imaging = true;
      _image = null;
      _imageError = null;
    });
    try {
      final image = await _outfit.generateImage(
        itemIds: [for (final item in suggestion.items) item.cloth.id],
        title: suggestion.title,
      );
      if (!mounted) return;
      setState(() => _image = image);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _imageError = e.detail);
    } on Exception {
      if (!mounted) return;
      setState(() => _imageError = 'サーバーに接続できませんでした');
    } finally {
      if (mounted) setState(() => _imaging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('確認'),
        actions: [
          IconButton(
            onPressed: _loadClothes,
            icon: const Icon(Icons.refresh),
            tooltip: '手持ちの服を読み直す',
          ),
        ],
      ),
      body: ValueListenableBuilder<MvLookupSnapshot>(
        valueListenable: widget.snapshot,
        builder: (context, s, _) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _Section(title: '入力', child: _inputs(s)),
            _Section(title: 'MV 情報', child: _mv(s)),
            _Section(title: 'アーティスト情報', child: _artist(s)),
            _Section(title: 'カルチャー情報', child: _culture(s)),
            _Section(title: 'ライブ情報', child: _live(s)),
            _Section(title: '手持ちの服', child: _wardrobeStrip()),
            _Section(title: 'コーデ提案', child: _proposal(context, s)),
          ],
        ),
      ),
    );
  }

  Widget _inputs(MvLookupSnapshot s) {
    if (s.mvQuery.isEmpty && s.liveQuery.isEmpty && s.liveDate == null) {
      return const _Missing('まだありません(MV 検索タブで入力してください)');
    }
    final liveDate = s.liveDate;
    final live = [
      if (s.liveQuery.isNotEmpty) s.liveQuery,
      if (liveDate != null) formatDate(liveDate),
    ].join(' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MV: ${s.mvQuery.isEmpty ? '(未入力)' : s.mvQuery}'),
        Text('ライブ: ${live.isEmpty ? '(未検索)' : live}'),
      ],
    );
  }

  Widget _mv(MvLookupSnapshot s) {
    final video = s.video;
    if (video == null) {
      return const _Missing('まだありません(MV 検索タブで動画を表示してください)');
    }
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 128,
            height: 72,
            child: video.thumbnailUrl.isEmpty
                ? ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.music_video)),
                  )
                : Image.network(
                    video.thumbnailUrl,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.music_video),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(video.songTitle, style: theme.textTheme.titleMedium),
              Text(video.artist),
              SelectableText(video.url, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _artist(MvLookupSnapshot s) {
    final video = s.video;
    if (video == null) {
      return const _Missing('まだありません(MV 検索タブで動画を表示してください)');
    }
    if (s.cultureLoading) return const _Missing('カルチャー情報を取得中です(MV 検索タブ)');
    final culture = s.culture;
    if (culture == null || !culture.identified) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(video.artist),
          const _Missing('カルチャー情報で特定できなかったため、動画の情報を表示しています'),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(culture.artist, style: Theme.of(context).textTheme.titleMedium),
        if (culture.background.summary.isNotEmpty)
          Text(culture.background.summary),
      ],
    );
  }

  Widget _culture(MvLookupSnapshot s) {
    if (s.cultureLoading) return const _Missing('カルチャー情報を取得中です(MV 検索タブ)');
    final culture = s.culture;
    if (culture == null) {
      return const _Missing('まだありません(MV 検索タブで動画を表示すると自動で取得されます)');
    }
    if (!culture.identified) {
      return _Missing('アーティストを特定できませんでした。${culture.message}');
    }
    final fashion = culture.fashion;
    final outfit = culture.mvOutfit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('MV のファッション'),
        _Chips(
          values: [...fashion.styles, ...fashion.colors, ...fashion.items],
        ),
        if (fashion.worldview.isNotEmpty) Text('世界観: ${fashion.worldview}'),
        const _Label('この MV の衣装'),
        if (!outfit.isOk)
          _Missing(outfit.message.isEmpty ? '映像を解析できませんでした' : outfit.message)
        else if (outfit.looks.isEmpty)
          const _Missing('映像から衣装を読み取れませんでした')
        else
          for (final look in outfit.looks) Text('・${_describeLook(look)}'),
        const _Label('音楽ジャンル'),
        if (culture.background.genres.isEmpty)
          const _Missing('情報が見つかりませんでした')
        else
          _Chips(values: culture.background.genres),
        // Google 検索のグラウンディング結果のため、出典と検索候補を添える(利用条件)
        GroundingFooter(
          sources: culture.sources,
          searchSuggestionsHtml: culture.searchSuggestionsHtml,
          webSearchQueries: culture.webSearchQueries,
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

  Widget _live(MvLookupSnapshot s) {
    final live = s.selectedLive;
    final result = s.liveResult;
    if (live == null) {
      return _Missing(
        result == null
            ? 'まだありません(MV 検索タブの「ライブを探す」で選んでください)'
            : 'ライブの候補から 1 件を選んでください(MV 検索タブ)',
      );
    }
    final date = live.date;
    final location = live.location.isEmpty ? '' : '(${live.location})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          live.liveName.isEmpty ? '(ライブ名不明)' : live.liveName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (live.artist != null) Text('アーティスト: ${live.artist}'),
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

  Widget _wardrobeStrip() {
    final clothes = _clothes;
    if (clothes == null) {
      if (_clothesError != null) {
        return Row(
          children: [
            Expanded(child: _Missing(_clothesError!)),
            TextButton(onPressed: _loadClothes, child: const Text('再読み込み')),
          ],
        );
      }
      return const LinearProgressIndicator();
    }
    if (clothes.isEmpty) {
      return const _Missing('まだありません(手持ちの服タブで登録してください)');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${clothes.length} 点'),
        const SizedBox(height: 4),
        WardrobeStrip(items: clothes, imageUrl: _wardrobe.imageUrl),
      ],
    );
  }

  Widget _proposal(BuildContext context, MvLookupSnapshot s) {
    final theme = Theme.of(context);
    final missing = _missing(s);
    final canSuggest = missing.isEmpty && !s.cultureLoading && !_busy;
    final suggestion = _suggestion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: canSuggest ? () => _suggest(s) : null,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('コーデを提案'),
        ),
        if (missing.isNotEmpty)
          _Missing('足りないもの: ${missing.join(' / ')}')
        else if (s.cultureLoading)
          const _Missing('カルチャー情報の取得が終わるまでお待ちください'),
        if (_suggesting) const _Progress('手持ちの服からコーデを考えています(十数秒かかることがあります)'),
        if (_suggestError != null) ...[
          Text(
            _suggestError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          FilledButton.tonalIcon(
            onPressed: canSuggest ? () => _suggest(s) : null,
            icon: const Icon(Icons.refresh),
            label: const Text('再試行'),
          ),
        ],
        if (suggestion != null) ...[
          const SizedBox(height: 12),
          Text(suggestion.title, style: theme.textTheme.titleLarge),
          if (suggestion.summary.isNotEmpty) Text(suggestion.summary),
          const SizedBox(height: 8),
          WardrobeStrip(
            items: [for (final item in suggestion.items) item.cloth],
            imageUrl: _wardrobe.imageUrl,
          ),
          for (final item in suggestion.items)
            Text(
              '・${item.role.isEmpty ? '' : '${item.role}: '}'
              '${item.cloth.attributes.category} — ${item.reason}',
            ),
          if (suggestion.points.isNotEmpty) ...[
            const _Label('ポイント'),
            for (final point in suggestion.points) Text('・$point'),
          ],
          if (suggestion.excludedCount > 0)
            _Missing('手持ちに無い服 ${suggestion.excludedCount} 点は提案から除きました'),
          const _Label('着用イメージ'),
          _outfitImage(theme),
        ],
      ],
    );
  }

  Widget _outfitImage(ThemeData theme) {
    if (_imaging) {
      return const _Progress('マネキンに着せた画像を作っています(数十秒かかることがあります)');
    }
    final error = _imageError;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _generateImage,
            icon: const Icon(Icons.refresh),
            label: const Text('画像を作り直す'),
          ),
        ],
      );
    }
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          image.bytes,
          key: const ValueKey('outfit-image'),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              const _Missing('画像を表示できませんでした'),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const _Missing('情報が見つかりませんでした');
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [for (final v in values) Chip(label: Text(v))],
    );
  }
}
