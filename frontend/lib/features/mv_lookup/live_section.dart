import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'culture_section.dart';
import 'grounding_footer.dart';
import 'live_models.dart';
import 'utils.dart';

/// ライブ情報の入力欄(テストで入力欄を区別するため)。
const liveQueryFieldKey = ValueKey('live-query');

/// ライブの「検索」ボタン。
const liveSearchButtonKey = ValueKey('live-search');

/// 詳細検索の「公演日」の欄。
const liveDateFieldKey = ValueKey('live-date');

/// 「② 行くライブを検索」のカード(spec 009。見た目は spec 015)。入力欄と、最大 3 件の候補を表示する。
///
/// 検索の実行・入力のロック・選択の状態は [MvLookupPanel] が持ち、ここは入力と表示だけを担う。
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
    this.cultureLoading = false,
  });

  /// ① ② のどこかで取得中。この間は入力を受け付けない
  final bool busy;

  /// カルチャー情報を取得中(入力を止めている理由を出す。spec 038)
  final bool cultureLoading;

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

  /// 候補を選んだ(null は選び直すために選択を外した)
  final ValueChanged<int?> onSelect;

  @override
  State<LiveSection> createState() => _LiveSectionState();
}

class _LiveSectionState extends State<LiveSection> {
  final _controller = TextEditingController();
  final _dateText = TextEditingController();
  DateTime? _date;
  String? _inputError;

  /// 詳細検索を開いているか(最初は閉じておく)
  bool _showDetails = false;

  @override
  void dispose() {
    _controller.dispose();
    _dateText.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.busy) return;
    final query = _controller.text.trim();
    if (query.isEmpty && _date == null) {
      // 両方空なら API を呼ばない(spec 009 AC-6)
      setState(() => _inputError = 'ライブ情報か日付を入力してください');
      return;
    }
    FocusScope.of(context).unfocus();
    // 結果が検索欄のすぐ下に見えるよう、詳細検索は閉じる(条件は残る)
    setState(() {
      _inputError = null;
      _showDetails = false;
    });
    widget.onSearch(query, _date);
  }

  void _setDate(DateTime? date) {
    setState(() {
      _date = date;
      _dateText.text = date == null ? '' : formatDate(date);
    });
  }

  Future<void> _pickDate() async {
    if (widget.busy) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 3, 12, 31),
      helpText: '公演日を選ぶ',
    );
    if (picked != null && mounted) _setDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy;
    final knownArtist = widget.knownArtist;
    return SectionCard(
      step: 2,
      done: widget.selectedIndex != null,
      title: '行くライブを検索',
      children: [
        const Hint('ライブ名・ツアー名・会場などのキーワードで公演を探します。日付で絞り込みたいときは「詳細検索」を開いてください。'),
        const SizedBox(height: 4),
        Hint(
          knownArtist == null
              ? 'アーティストは入力から特定します'
              : 'アーティスト: $knownArtist(表示中の動画から)',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: liveQueryFieldKey,
                controller: _controller,
                enabled: !busy,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'ライブ名・ツアー名・会場など',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: liveSearchButtonKey,
              onPressed: busy ? null : _submit,
              child: widget.loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('検索'),
            ),
          ],
        ),
        // 入力を止めている理由(spec 038 AC-19)
        if (widget.cultureLoading) const CultureLockHint(),
        _DetailToggle(
          open: _showDetails,
          count: _date == null ? 0 : 1,
          onTap: () => setState(() => _showDetails = !_showDetails),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _showDetails
              ? _detailPanel(busy)
              : const SizedBox(width: double.infinity),
        ),
        if (_inputError != null) ...[
          const SizedBox(height: 8),
          ErrorText(_inputError!),
        ],
        _buildResult(context),
      ],
    );
  }

  /// 詳細検索(任意項目)。今は公演日だけ。
  Widget _detailPanel(bool busy) {
    return SoftBox(
      margin: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Hint('公演日で絞り込みます。日付だけでも検索できます。'),
          const SizedBox(height: 12),
          TextField(
            key: liveDateFieldKey,
            controller: _dateText,
            readOnly: true,
            enabled: !busy,
            onTap: _pickDate,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: '公演日',
              suffixIcon: _date == null
                  ? const Icon(Icons.calendar_today, size: 18)
                  : IconButton(
                      tooltip: '公演日を消す',
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: busy ? null : () => _setDate(null),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final result = widget.result;
    if (widget.loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ライブ情報を調べています',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Hint('Google 検索で公演と当日の天気を調べているため、数十秒かかることがあります'),
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
            const Text(
              'ライブ情報を取得できませんでした',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ErrorText(widget.error!),
            const SizedBox(height: 8),
            OutlinedButton.icon(
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
            const Text(
              '該当するライブが見つかりませんでした',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (result.message.isNotEmpty &&
                result.message != '該当するライブが見つかりませんでした。')
              Text(result.message),
            footer,
          ],
        ),
      );
    }

    final selected = result.candidates
        .where((c) => c.index == widget.selectedIndex)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selected == null) ...[
            Text(
              '見つかった公演(${result.candidates.length}件)— 行く公演を選んでください',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final candidate in result.candidates)
              _LiveCandidateTile(
                candidate: candidate,
                onTap: widget.busy
                    ? null
                    : () => widget.onSelect(candidate.index),
              ),
          ] else
            // 選んだ公演だけを出す。「変更」で選び直せる(tadasii と同じ)
            _LiveCandidateTile(
              candidate: selected,
              selected: true,
              onTap: widget.busy ? null : () => widget.onSelect(null),
            ),
          footer,
        ],
      ),
    );
  }
}

/// 「詳細検索」の開閉ボタン。閉じていても入力済みの件数を表示する。
class _DetailToggle extends StatelessWidget {
  const _DetailToggle({
    required this.open,
    required this.count,
    required this.onTap,
  });

  final bool open;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextButton.icon(
          onPressed: onTap,
          icon: AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.expand_more),
          ),
          label: Text('詳細検索(任意)${count > 0 ? '・$count件入力中' : ''}'),
        ),
      ),
    );
  }
}

/// ライブの候補(tadasii の候補タイル)。選んだ候補は薄い赤地・赤い枠・「変更」。
class _LiveCandidateTile extends StatelessWidget {
  const _LiveCandidateTile({
    required this.candidate,
    required this.onTap,
    this.selected = false,
  });

  final LiveCandidate candidate;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final date = candidate.date;
    final location = candidate.location.isEmpty
        ? ''
        : '(${candidate.location})';
    const detail = TextStyle(fontSize: 14);
    final palette = AppPalette.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? palette.selected : AppColors.soft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? palette.accent : Colors.transparent,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.music_note,
                color: selected ? palette.accent : AppColors.muted,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (candidate.artist != null)
                      Text('アーティスト: ${candidate.artist}', style: detail),
                    Text(
                      '場所: ${candidate.venue.isEmpty ? '不明' : candidate.venue}$location',
                      style: detail,
                    ),
                    Text(
                      '日付: ${date == null ? '不明' : formatDate(date)}',
                      style: detail,
                    ),
                    Text('天気: ${candidate.weather.description}', style: detail),
                    if (candidate.sourceIndices.isNotEmpty)
                      Text(
                        '出典: ${candidate.sourceIndices.map((i) => '[$i]').join(' ')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              selected
                  ? Text('変更', style: TextStyle(color: palette.accent))
                  : const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
