import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'culture_models.dart';
import 'culture_repository.dart';
import 'culture_section.dart';
import 'live_models.dart';
import 'live_repository.dart';
import 'live_section.dart';
import 'mv_models.dart';
import 'mv_repository.dart';
import 'utils.dart';

/// MV の入力欄(テストで入力欄を区別するため)。
const mvQueryFieldKey = ValueKey('mv-query');

/// ライブ情報の検索条件(再試行で同じ条件を使うために残す)。
typedef _LiveQuery = ({String query, DateTime? date, String? artist});

/// YouTube の URL または MV 名から、MV のメタ情報(アーティスト名・曲名・リンクなど)を調べる画面。
///
/// - 動画情報が表示されたら、そのアーティストのカルチャー情報(spec 008)も自動で調べる。
/// - 候補を選ぶと、画面を切り替えずにその候補の直下に情報を展開する(spec 009)。
/// - 下部の「ライブを探す」で、ライブ情報と当日の天気を調べられる(spec 009)。
class MvLookupScreen extends StatefulWidget {
  const MvLookupScreen({
    super.key,
    this.repository,
    this.cultureRepository,
    this.liveRepository,
  });

  final MvRepository? repository;
  final CultureRepository? cultureRepository;
  final LiveRepository? liveRepository;

  @override
  State<MvLookupScreen> createState() => _MvLookupScreenState();
}

class _MvLookupScreenState extends State<MvLookupScreen> {
  late final MvRepository _repository = widget.repository ?? MvRepository();
  late final CultureRepository _cultureRepository =
      widget.cultureRepository ?? CultureRepository();
  late final LiveRepository _liveRepository =
      widget.liveRepository ?? LiveRepository();
  final _controller = TextEditingController();
  bool _loading = false;
  // 0 件の表示と初期表示を区別するため
  bool _searched = false;
  String? _error;
  List<MvCandidate> _candidates = const [];

  /// 展開中の候補の動画 ID(候補から選んだとき)
  String? _expandedVideoId;
  MvVideo? _video;

  bool _cultureLoading = false;
  CultureReport? _culture;
  String? _cultureError;

  bool _liveLoading = false;
  LiveSearchResult? _live;
  String? _liveError;
  int? _selectedLiveIndex;
  _LiveQuery? _lastLiveQuery;

  /// 動画情報・カルチャー情報・ライブ情報のいずれかを取得中。この間は他の入力を受け付けない
  bool get _busy => _loading || _cultureLoading || _liveLoading;

  /// 表示中の動画のアーティスト。カルチャー情報で特定した名前を優先し、
  /// 無ければタイトルを分解できた場合の名前を使う(spec 009)。
  String? get _knownArtist {
    final video = _video;
    if (video == null) return null;
    final culture = _culture;
    if (culture != null && culture.identified && culture.artist.isNotEmpty) {
      return culture.artist;
    }
    return video.titleParsed ? video.artist : null;
  }

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
    await _lookup(query);
  }

  /// URL なら動画情報、MV 名なら候補一覧が返る。
  ///
  /// 候補から選んだとき([candidateId])は、候補一覧を残したままその候補の直下に展開する。
  /// 動画情報が表示されたら(URL 入力・候補の選択のどちらでも)カルチャー情報の取得を始める。
  Future<void> _lookup(String query, {String? candidateId}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (candidateId != null) {
        // 前の展開を閉じて、選んだ候補を展開する(前の結果は使い回さない)
        _expandedVideoId = candidateId;
        _video = null;
        _culture = null;
        _cultureError = null;
      }
    });

    MvVideo? video;
    try {
      final result = await _repository.lookup(query);
      if (!mounted) return;
      video = result.video;
      setState(() {
        _searched = true;
        _video = result.video;
        if (candidateId == null) {
          _candidates = result.candidates;
          _expandedVideoId = null;
        }
        // 取得が始まるまでに入力できる隙間を作らないよう、ここでロックを掛けておく
        _culture = null;
        _cultureError = null;
        _cultureLoading = result.video != null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.detail;
        if (candidateId != null) _expandedVideoId = null;
      });
    } on Exception {
      // バックエンド自体に繋がらない場合(http の ClientException など)
      if (!mounted) return;
      setState(() {
        _error = 'サーバーに接続できませんでした';
        if (candidateId != null) _expandedVideoId = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    if (video != null && mounted) await _researchCulture(video);
  }

  /// 候補のタップ。展開中の候補なら閉じ、別の候補なら展開し直す。
  void _onCandidateTap(MvCandidate candidate) {
    if (_busy) return;
    if (_expandedVideoId == candidate.videoId) {
      setState(() {
        _expandedVideoId = null;
        _video = null;
        _culture = null;
        _cultureError = null;
      });
      return;
    }
    _lookup(candidate.url, candidateId: candidate.videoId);
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

  /// ライブ情報を Gemini に調べさせる。表示中のアーティストが分かっていれば条件に添える。
  Future<void> _searchLive(String query, DateTime? date) async {
    if (_busy) return;
    await _runLiveSearch((query: query, date: date, artist: _knownArtist));
  }

  Future<void> _runLiveSearch(_LiveQuery request) async {
    setState(() {
      _lastLiveQuery = request;
      _liveLoading = true;
      _live = null;
      _liveError = null;
      _selectedLiveIndex = null;
    });

    try {
      final result = await _liveRepository.search(
        query: request.query,
        date: request.date,
        artist: request.artist,
      );
      if (!mounted) return;
      setState(() => _live = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _liveError = e.detail);
    } on Exception {
      if (!mounted) return;
      setState(() => _liveError = 'サーバーに接続できませんでした');
    } finally {
      if (mounted) setState(() => _liveLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastLive = _lastLiveQuery;
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
                    key: mvQueryFieldKey,
                    controller: _controller,
                    // 取得中は他の情報を受け付けない(spec 008 AC-2 / spec 009 AC-14)
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
          // 候補の動画情報の取得中は、その候補の下に進捗を出す
          if (_loading && _expandedVideoId == null)
            const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                ..._buildResults(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: LiveSection(
                    busy: _busy,
                    loading: _liveLoading,
                    knownArtist: _knownArtist,
                    result: _live,
                    error: _liveError,
                    selectedIndex: _selectedLiveIndex,
                    onSearch: _searchLive,
                    onRetry: lastLive == null
                        ? () {}
                        : () => _runLiveSearch(lastLive),
                    onSelect: (index) =>
                        setState(() => _selectedLiveIndex = index),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResults() {
    final video = _video;
    if (_candidates.isEmpty) {
      // URL を入力した場合は、候補の代わりに動画情報を出す
      if (video != null) {
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _videoPanel(video),
          ),
        ];
      }
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
          child: Center(
            child: Text(
              _searched
                  ? '該当する動画が見つかりませんでした'
                  : 'YouTube の URL または MV 名を入力して調べてください',
            ),
          ),
        ),
      ];
    }

    return [
      for (final candidate in _candidates) ...[
        _CandidateTile(
          candidate: candidate,
          expanded: candidate.videoId == _expandedVideoId,
          onTap: _busy ? null : () => _onCandidateTap(candidate),
        ),
        if (candidate.videoId == _expandedVideoId)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: video == null
                ? const LinearProgressIndicator()
                : _videoPanel(video),
          ),
      ],
    ];
  }

  /// 動画情報とカルチャー情報。
  Widget _videoPanel(MvVideo video) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              _Field(label: '公開日', value: formatDate(publishedAt)),
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
  const _CandidateTile({
    required this.candidate,
    required this.expanded,
    required this.onTap,
  });

  final MvCandidate candidate;

  /// この候補の直下に情報を展開しているか
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    return InkWell(
      onTap: onTap,
      child: Ink(
        color: expanded ? theme.colorScheme.secondaryContainer : null,
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
              Icon(expanded ? Icons.expand_more : Icons.chevron_right),
            ],
          ),
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
