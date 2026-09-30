import 'package:flutter/material.dart';

import 'grounding_footer.dart';
import 'live_models.dart';
import 'utils.dart';

/// ライブ情報の入力欄(テストで入力欄を区別するため)。
const liveQueryFieldKey = ValueKey('live-query');

/// ライブ情報の検索(spec 009)。入力欄と、最大 3 件の候補を表示する。
///
/// 検索の実行・入力のロック・選択の状態は MV 検索画面が持ち、ここは入力と表示だけを担う。
class LiveSection extends StatefulWidget {
  const LiveSection({
    super.key,
    required this.busy,
    required this.loading,
    required this.onSearch,
    required this.onRetry,
    required this.onSelect,
    this.knownArtist,
    this.result,
    this.error,
    this.selectedIndex,
  });

  /// MV 検索画面のどこかで取得中。この間は入力を受け付けない
  final bool busy;

  /// ライブ情報を取得中
  final bool loading;

  /// 表示中の動画で分かっているアーティスト名
  final String? knownArtist;
  final LiveSearchResult? result;
  final String? error;

  /// 選んだ候補の番号(LiveCandidate.index)
  final int? selectedIndex;
  final void Function(String query, DateTime? date) onSearch;
  final VoidCallback onRetry;
  final ValueChanged<int> onSelect;

  @override
  State<LiveSection> createState() => _LiveSectionState();
}

class _LiveSectionState extends State<LiveSection> {
  final _controller = TextEditingController();
  DateTime? _date;
  String? _inputError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.busy) return;
    final query = _controller.text.trim();
    if (query.isEmpty && _date == null) {
      // 両方空なら API を呼ばない(AC-6)
      setState(() => _inputError = 'ライブ情報か日付を入力してください');
      return;
    }
    setState(() => _inputError = null);
    widget.onSearch(query, _date);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 3, 12, 31),
      helpText: '公演日を選ぶ',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = widget.busy;
    final date = _date;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ライブを探す', style: theme.textTheme.titleLarge),
            Text(
              widget.knownArtist == null
                  ? 'アーティストは入力から特定します'
                  : 'アーティスト: ${widget.knownArtist}(表示中の動画から)',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: liveQueryFieldKey,
                    controller: _controller,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      hintText: 'ライブ名・ツアー名・会場など',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : _pickDate,
                  icon: const Icon(Icons.event),
                  label: Text(date == null ? '日付' : formatDate(date)),
                ),
                if (date != null)
                  IconButton(
                    onPressed: busy ? null : () => setState(() => _date = null),
                    icon: const Icon(Icons.clear),
                    tooltip: '日付を消す',
                  ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: busy ? null : _submit,
                  icon: const Icon(Icons.travel_explore),
                  tooltip: 'ライブを探す',
                ),
              ],
            ),
            if (_inputError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _inputError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            _buildResult(context),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    if (widget.loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ライブ情報を調べています', style: theme.textTheme.titleMedium),
                  Text(
                    'Google 検索で公演と当日の天気を調べているため、数十秒かかることがあります',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (widget.error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ライブ情報を取得できませんでした', style: theme.textTheme.titleMedium),
            Text(
              widget.error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: widget.busy ? null : widget.onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ),
      );
    }

    if (result == null) return const SizedBox.shrink();

    final footer = GroundingFooter(
      sources: result.sources,
      searchSuggestionsHtml: result.searchSuggestionsHtml,
      webSearchQueries: result.webSearchQueries,
    );
    if (!result.found) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('該当するライブが見つかりませんでした', style: theme.textTheme.titleMedium),
            if (result.message.isNotEmpty &&
                result.message != '該当するライブが見つかりませんでした。')
              Text(result.message),
            footer,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('行くライブを選んでください', style: theme.textTheme.bodySmall),
          for (final candidate in result.candidates)
            _LiveCandidateCard(
              candidate: candidate,
              selected: candidate.index == widget.selectedIndex,
              onTap: widget.busy
                  ? null
                  : () => widget.onSelect(candidate.index),
            ),
          footer,
        ],
      ),
    );
  }
}

class _LiveCandidateCard extends StatelessWidget {
  const _LiveCandidateCard({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final LiveCandidate candidate;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = candidate.date;
    final location = candidate.location.isEmpty
        ? ''
        : '(${candidate.location})';
    return Card(
      color: selected ? scheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.liveName.isEmpty
                          ? '(ライブ名不明)'
                          : candidate.liveName,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (candidate.artist != null)
                      Text('アーティスト: ${candidate.artist}'),
                    Text(
                      '場所: ${candidate.venue.isEmpty ? '不明' : candidate.venue}$location',
                    ),
                    Text('日付: ${date == null ? '不明' : formatDate(date)}'),
                    Text('天気: ${candidate.weather.description}'),
                    if (candidate.sourceIndices.isNotEmpty)
                      Text(
                        '出典: ${candidate.sourceIndices.map((i) => '[$i]').join(' ')}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
