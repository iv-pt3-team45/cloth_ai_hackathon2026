import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_screen.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';
import 'package:tx_hackathon_gc/main.dart';

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
    MaterialApp(
      home: MvLookupScreen(
        repository: repo,
        cultureRepository: FakeCultureRepository(),
        liveRepository: FakeLiveRepository(),
      ),
    ),
  );
}

Future<void> _submit(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(mvQueryFieldKey), query);
  await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
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
    expect(
      find.text('https://www.youtube.com/watch?v=abcDEF12345'),
      findsOneWidget,
    );
    expect(find.text('Ayase / YOASOBI'), findsOneWidget);
    expect(find.text('概要欄'), findsOneWidget);
    expect(find.textContaining('分解できなかった'), findsNothing);
    expect(find.text('候補一覧に戻る'), findsNothing);
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

    expect(find.text('2023/06/15'), findsOneWidget);
  });

  testWidgets(
    'MV 名を入力すると候補が出て、選ぶとその候補の直下にリンクが表示される(007 AC-3, AC-4 / 009 AC-1)',
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
      const link = 'https://www.youtube.com/watch?v=abcDEF12345';
      expect(find.text(link), findsOneWidget);
      // 画面は切り替わらず、候補一覧は残る。情報は選んだ候補と次の候補の間に展開される
      expect(find.text('アイドル 歌ってみた'), findsOneWidget);
      final selectedTop = tester
          .getTopLeft(find.text('YOASOBI「アイドル」 Official Music Video').first)
          .dy;
      final linkTop = tester.getTopLeft(find.text(link)).dy;
      final nextTop = tester.getTopLeft(find.text('アイドル 歌ってみた')).dy;
      expect(selectedTop < linkTop && linkTop < nextTop, isTrue);
    },
  );

  testWidgets('展開中の候補をもう一度押すと閉じる(009 AC-3)', (tester) async {
    final repo = FakeMvRepository(
      (query) async => query.startsWith('https://')
          ? const MvLookupResult(inputType: 'url', video: _video)
          : const MvLookupResult(inputType: 'keyword', candidates: _candidates),
    );
    await _pumpScreen(tester, repo);
    await _submit(tester, 'アイドル');

    await tester.tap(find.text('YOASOBI「アイドル」 Official Music Video'));
    await tester.pumpAndSettle();
    // 展開していない候補だけが右向きの矢印になる(下向きは概要欄の開閉にも使われるため数えない)
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    // 展開後は動画タイトルが 2 か所(候補と動画情報)に出るため、候補の方を押す
    await tester.tap(find.text('YOASOBI「アイドル」 Official Music Video').first);
    await tester.pumpAndSettle();

    expect(
      find.text('https://www.youtube.com/watch?v=abcDEF12345'),
      findsNothing,
    );
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    expect(find.text('アイドル 歌ってみた'), findsOneWidget);
    // 閉じるだけなので問い合わせは増えない
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

  testWidgets('API のエラーは detail をバナーに出す(AC-7, AC-10)', (tester) async {
    final repo = FakeMvRepository(
      (query) async => throw ApiException(
        '{"detail":"YouTube API のクォータ(1 日の利用上限)を超えました。"}',
        statusCode: 503,
      ),
    );
    await _pumpScreen(tester, repo);

    await _submit(tester, 'アイドル');

    expect(find.text('YouTube API のクォータ(1 日の利用上限)を超えました。'), findsOneWidget);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('空のまま実行すると入力エラーを出し、API は呼ばない(AC-8)', (tester) async {
    final repo = FakeMvRepository(_videoResult);
    await _pumpScreen(tester, repo);

    await _submit(tester, '   ');

    expect(find.textContaining('入力が空です'), findsOneWidget);
    expect(repo.queries, isEmpty);
  });

  testWidgets('ナビゲーションで MV 検索とチャットを切り替えられる', (tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('YouTube の URL または MV 名を入力して調べてください'), findsOneWidget);

    await tester.tap(find.text('チャット'));
    await tester.pumpAndSettle();

    expect(find.text('メッセージを送信してください'), findsOneWidget);
  });
}
