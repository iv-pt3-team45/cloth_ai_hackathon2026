import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/core/link.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_panel.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';

import 'mv_lookup_fakes.dart';

// サムネイルは空にする(テストでネットワークから画像を読まないため)
const _video = MvVideo(
  videoId: 'abcDEF12345',
  url: 'https://www.youtube.com/watch?v=abcDEF12345',
  artist: 'YOASOBI',
  songTitle: 'アイドル',
  titleParsed: true,
  title: 'YOASOBI「アイドル」 Official Music Video',
  channelTitle: 'Ayase / YOASOBI',
  description: '概要欄のテキスト',
);

const _candidates = [
  MvCandidate(
    videoId: 'abcDEF12345',
    url: 'https://www.youtube.com/watch?v=abcDEF12345',
    title: 'YOASOBI「アイドル」 Official Music Video',
    channelTitle: 'Ayase / YOASOBI',
  ),
  MvCandidate(
    videoId: 'video000001',
    url: 'https://www.youtube.com/watch?v=video000001',
    title: 'アイドル 歌ってみた',
    channelTitle: 'Someone',
  ),
];

Future<MvLookupResult> _videoResult(String query) async =>
    const MvLookupResult(inputType: 'url', video: _video);

// 動画が表示されるとカルチャー情報の取得が自動で始まるため、そちらもフェイクにする
Future<void> _pumpScreen(WidgetTester tester, FakeMvRepository repo) {
  // 展開した情報の下の候補まで一度に描画されるよう、画面を縦に長くする
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    panelApp(
      MvLookupPanel(
        repository: repo,
        cultureRepository: FakeCultureRepository(),
        liveRepository: FakeLiveRepository(),
      ),
    ),
  );
}

Future<void> _submit(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(mvQueryFieldKey), query);
  await tester.tap(find.byKey(mvSearchButtonKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('URL を入力すると動画のメタ情報が表示される(AC-1)', (tester) async {
    final repo = FakeMvRepository(_videoResult);
    await _pumpScreen(tester, repo);

    expect(find.text('YouTube の URL または MV 名を入力して調べてください'), findsOneWidget);

    await _submit(tester, 'https://youtu.be/abcDEF12345');

    expect(repo.queries, ['https://youtu.be/abcDEF12345']);
    expect(find.text('アイドル'), findsOneWidget);
    expect(find.text('YOASOBI'), findsOneWidget);
    expect(find.textContaining('分解できなかった'), findsNothing);
    expect(find.text('候補一覧に戻る'), findsNothing);
  });

  testWidgets('動画の情報は要点だけを出し、「詳細」で残りを開閉する(038 AC-1, AC-2)', (tester) async {
    await _pumpScreen(tester, FakeMvRepository(_videoResult));
    await _submit(tester, 'https://youtu.be/abcDEF12345');

    expect(find.text('アイドル'), findsOneWidget);
    expect(find.text('YOASOBI'), findsOneWidget);
    expect(find.text('YouTube で開く'), findsOneWidget);
    // 動画タイトル・チャンネル・概要欄は初期は出さない
    expect(find.text('YOASOBI「アイドル」 Official Music Video'), findsNothing);
    expect(find.text('Ayase / YOASOBI'), findsNothing);
    expect(find.text('概要欄のテキスト'), findsNothing);

    await tester.tap(find.text('詳細'));
    await tester.pumpAndSettle();

    expect(find.text('YOASOBI「アイドル」 Official Music Video'), findsOneWidget);
    expect(find.text('Ayase / YOASOBI'), findsOneWidget);
    expect(find.text('概要欄のテキスト'), findsOneWidget);

    await tester.tap(find.text('詳細'));
    await tester.pumpAndSettle();

    expect(find.text('Ayase / YOASOBI'), findsNothing);
  });

  testWidgets('「YouTube で開く」で動画の URL を開き、開けなければ知らせる(038 AC-3)', (tester) async {
    final opened = <Uri>[];
    var result = true;
    final original = openUrl;
    openUrl = (uri) async {
      opened.add(uri);
      return result;
    };
    addTearDown(() => openUrl = original);
    await _pumpScreen(tester, FakeMvRepository(_videoResult));
    await _submit(tester, 'https://youtu.be/abcDEF12345');

    await tester.tap(find.text('YouTube で開く'));
    await tester.pump();
    expect(opened.single.toString(), _video.url);
    expect(find.text('リンクを開けませんでした'), findsNothing);

    result = false;
    await tester.tap(find.text('YouTube で開く'));
    await tester.pump();
    expect(find.text('リンクを開けませんでした'), findsOneWidget);
  });

  testWidgets('公開日を表示する', (tester) async {
    final repo = FakeMvRepository(
      (query) async => MvLookupResult(
        inputType: 'url',
        video: MvVideo(
          videoId: _video.videoId,
          url: _video.url,
          artist: _video.artist,
          songTitle: _video.songTitle,
          titleParsed: true,
          title: _video.title,
          channelTitle: _video.channelTitle,
          // どのタイムゾーンで実行しても日付が変わらない時刻にする
          publishedAt: DateTime.utc(2023, 6, 15, 12),
        ),
      ),
    );
    await _pumpScreen(tester, repo);

    await _submit(tester, 'https://youtu.be/abcDEF12345');
    await tester.tap(find.text('詳細'));
    await tester.pumpAndSettle();

    expect(find.text('2023/06/15'), findsOneWidget);
  });

  testWidgets(
    'MV 名を入力すると候補が出て、選ぶと選んだ候補だけを残して直下に情報を出す(007 AC-3, AC-4 / 038 AC-4)',
    (tester) async {
      final repo = FakeMvRepository(
        (query) async => query.startsWith('https://')
            ? const MvLookupResult(inputType: 'url', video: _video)
            : const MvLookupResult(
                inputType: 'keyword',
                candidates: _candidates,
              ),
      );
      await _pumpScreen(tester, repo);

      await _submit(tester, 'アイドル');

      expect(find.text('アイドル 歌ってみた'), findsOneWidget);
      expect(find.text('Someone'), findsOneWidget);

      await tester.tap(find.text('YOASOBI「アイドル」 Official Music Video'));
      await tester.pumpAndSettle();

      // 候補の URL をそのまま送り直す
      expect(repo.queries, [
        'アイドル',
        'https://www.youtube.com/watch?v=abcDEF12345',
      ]);
      // 選ばなかった候補は隠れ、選んだ候補の直下に動画の情報が出る
      expect(find.text('アイドル 歌ってみた'), findsNothing);
      expect(find.text('選んだ動画'), findsOneWidget);
      expect(find.text('変更'), findsOneWidget);
      final selectedTop = tester
          .getTopLeft(find.text('YOASOBI「アイドル」 Official Music Video'))
          .dy;
      final openTop = tester.getTopLeft(find.text('YouTube で開く')).dy;
      expect(selectedTop < openTop, isTrue);
    },
  );

  testWidgets('「変更」で候補の一覧に戻り、動画の情報は消える(038 AC-5)', (tester) async {
    final repo = FakeMvRepository(
      (query) async => query.startsWith('https://')
          ? const MvLookupResult(inputType: 'url', video: _video)
          : const MvLookupResult(inputType: 'keyword', candidates: _candidates),
    );
    await _pumpScreen(tester, repo);
    await _submit(tester, 'アイドル');

    await tester.tap(find.text('YOASOBI「アイドル」 Official Music Video'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.text('カルチャー情報'), findsOneWidget);

    await tester.tap(find.text('変更'));
    await tester.pumpAndSettle();

    expect(find.text('YouTube で開く'), findsNothing);
    expect(find.text('カルチャー情報'), findsNothing);
    expect(find.text('変更'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    expect(find.text('アイドル 歌ってみた'), findsOneWidget);
    // 戻すだけなので問い合わせは増えない
    expect(repo.queries, hasLength(2));
  });

  testWidgets('分解できなかった場合は注記を出す(AC-6)', (tester) async {
    final repo = FakeMvRepository(
      (query) async => const MvLookupResult(
        inputType: 'url',
        video: MvVideo(
          videoId: 'abcDEF12345',
          url: 'https://www.youtube.com/watch?v=abcDEF12345',
          artist: '米津玄師',
          songTitle: 'Lemon',
          titleParsed: false,
          title: 'Lemon',
          channelTitle: '米津玄師',
        ),
      ),
    );
    await _pumpScreen(tester, repo);

    await _submit(tester, 'https://youtu.be/abcDEF12345');

    expect(find.textContaining('分解できなかった'), findsOneWidget);
  });

  testWidgets('候補が 0 件なら見つからない旨を出す(AC-9)', (tester) async {
    final repo = FakeMvRepository(
      (query) async => const MvLookupResult(inputType: 'keyword'),
    );
    await _pumpScreen(tester, repo);

    await _submit(tester, '存在しない曲名');

    expect(find.text('該当する動画が見つかりませんでした'), findsOneWidget);
  });

  testWidgets('API のエラーは detail を入力欄の下に出し、次の検索で消す(AC-7, AC-10)', (
    tester,
  ) async {
    final repo = FakeMvRepository(
      (query) async => throw ApiException(
        '{"detail":"YouTube API のクォータ(1 日の利用上限)を超えました。"}',
        statusCode: 503,
      ),
    );
    await _pumpScreen(tester, repo);

    await _submit(tester, 'アイドル');

    expect(find.text('YouTube API のクォータ(1 日の利用上限)を超えました。'), findsOneWidget);

    repo.respond = _videoResult;
    await _submit(tester, 'https://youtu.be/abcDEF12345');

    expect(find.text('YouTube API のクォータ(1 日の利用上限)を超えました。'), findsNothing);
  });

  testWidgets('空のまま実行すると入力エラーを出し、API は呼ばない(AC-8)', (tester) async {
    final repo = FakeMvRepository(_videoResult);
    await _pumpScreen(tester, repo);

    await _submit(tester, '   ');

    expect(find.textContaining('入力が空です'), findsOneWidget);
    expect(repo.queries, isEmpty);
  });
}
