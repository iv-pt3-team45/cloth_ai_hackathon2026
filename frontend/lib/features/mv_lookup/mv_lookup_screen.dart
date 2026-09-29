import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'culture_models.dart';
import 'culture_repository.dart';
import 'culture_section.dart';
import 'mv_models.dart';
import 'mv_repository.dart';

/// YouTube の URL または MV 名から、MV のメタ情報(アーティスト名・曲名・リンクなど)を調べる画面。
///
/// 動画情報が表示されたら、そのアーティストのカルチャー情報(spec 008)も自動で調べる。
class MvLookupScreen extends StatefulWidget {
  const MvLookupScreen({super.key, this.repository, this.cultureRepository});

  final MvRepository? repository;
  final CultureRepository? cultureRepository;

  @override
  State<MvLookupScreen> createState() => _MvLookupScreenState();
}

class _MvLookupScreenState extends State<MvLookupScreen> {
  late final MvRepository _repository = widget.repository ?? MvRepository();
  late final CultureRepository _cultureRepository =
      widget.cultureRepository ?? CultureRepository();
  final _controller = TextEditingController();
  bool _loading = false;
  // 0 件の表示と初期表示を区別するため
  bool _searched = false;
  String? _error;
  List<MvCandidate> _candidates = const [];
  MvVideo? _video;

  bool _cultureLoading = false;
  CultureReport? _culture;
  String? _cultureError;

  /// 動画情報またはカルチャー情報の取得中。この間は他の入力を受け付けない
  bool get _busy => _loading || _cultureLoading;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() => _error = '入力が空です。YouTube の URL または MV 名を入力してください');
      return;
    }
    await _lookup(query, fromCandidate: false);
  }

  /// URL なら動画情報、MV 名なら候補一覧が返る。
  ///
  /// 候補から選んだとき([fromCandidate])は候補一覧を残し、「候補一覧に戻る」で戻れるようにする。
  /// 動画情報が表示されたら(URL 入力・候補の選択のどちらでも)カルチャー情報の取得を始める。
  Future<void> _lookup(String query, {required bool fromCandidate}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    MvVideo? video;
    try {
      final result = await _repository.lookup(query);
      if (!mounted) return;
      video = result.video;
      setState(() {
        _searched = true;
        _video = result.video;
        if (!fromCandidate) _candidates = result.candidates;
        // 前の動画の結果は使い回さない。取得が始まるまでに入力できる隙間を作らないよう、
        // ここでロックを掛けておく
        _culture = null;
        _cultureError = null;
        _cultureLoading = result.video != null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.detail);
    } on Exception {
      // バックエンド自体に繋がらない場合(http の ClientException など)
      if (!mounted) return;
      setState(() => _error = 'サーバーに接続できませんでした');
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    if (video != null && mounted) await _researchCulture(video);
  }

  /// 動画のアーティストのカルチャー情報を Gemini に調べさせる(数十秒かかる)。
  Future<void> _researchCulture(MvVideo video) async {
    setState(() {
      _cultureLoading = true;
      _culture = null;
      _cultureError = null;
    });

    try {
      final report = await _cultureRepository.research(video);
      if (!mounted) return;
      setState(() => _culture = report);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _cultureError = e.detail);
    } on Exception {
      if (!mounted) return;
      setState(() => _cultureError = 'サーバーに接続できませんでした');
    } finally {
      if (mounted) setState(() => _cultureLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MV 検索')),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    // カルチャー情報の取得中は他の情報を受け付けない(spec 008 AC-2)
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      hintText: 'YouTube の URL または MV 名',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                // 通信中は押せなくする(検索は 1 回 100 ユニット消費するため連打させない)
                IconButton.filled(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.search),
                  tooltip: '調べる',
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _buildResult()),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final video = _video;
    if (video != null) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_candidates.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => setState(() => _video = null),
                icon: const Icon(Icons.arrow_back),
                label: const Text('候補一覧に戻る'),
              ),
            ),
          _VideoDetail(video: video),
          const SizedBox(height: 12),
          CultureSection(
            loading: _cultureLoading,
            report: _culture,
            error: _cultureError,
            onRetry: () => _researchCulture(video),
          ),
        ],
      );
    }

    if (_candidates.isNotEmpty) {
      return ListView.builder(
        itemCount: _candidates.length,
        itemBuilder: (context, index) {
          final candidate = _candidates[index];
          return _CandidateTile(
            candidate: candidate,
            onTap: _busy
                ? null
                : () => _lookup(candidate.url, fromCandidate: true),
          );
        },
      );
    }

    return Center(
      child: Text(
        _searched ? '該当する動画が見つかりませんでした' : 'YouTube の URL または MV 名を入力して調べてください',
      ),
    );
  }
}

class _VideoDetail extends StatelessWidget {
  const _VideoDetail({required this.video});

  final MvVideo video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final publishedAt = video.publishedAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (video.thumbnailUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _Thumbnail(url: video.thumbnailUrl, maxWidth: 480),
              ),
              const SizedBox(height: 12),
            ],
            Text(video.songTitle, style: theme.textTheme.headlineSmall),
            Text(video.artist, style: theme.textTheme.titleMedium),
            if (!video.titleParsed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'タイトルから分解できなかったため、チャンネル名と動画タイトルをそのまま表示しています',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const Divider(height: 24),
            _Field(label: 'リンク', value: video.url),
            _Field(label: '動画タイトル', value: video.title),
            _Field(label: 'チャンネル', value: video.channelTitle),
            if (publishedAt != null)
              _Field(label: '公開日', value: _formatDate(publishedAt)),
            if (video.description.isNotEmpty)
              ExpansionTile(
                title: const Text('概要欄'),
                tilePadding: EdgeInsets.zero,
                expandedAlignment: Alignment.centerLeft,
                children: [SelectableText(video.description)],
              ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          // 選択してコピーできるようにする(リンクを後で使うため)
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate, required this.onTap});

  final MvCandidate candidate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _Thumbnail(url: candidate.thumbnailUrl, maxWidth: 160),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(candidate.channelTitle, style: textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 16:9 のサムネイル。読み込めない場合はアイコンを出す。
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url, required this.maxWidth});

  final String url;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.music_video)),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: url.isEmpty
            ? placeholder
            : Image.network(
                url,
                fit: BoxFit.cover,
                // Flutter Web(CanvasKit)は CORS ヘッダの無い画像を描画できないため、
                // その場合は <img> 要素で表示させる
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)}';
}
