import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/api_client.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_controller.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_models.dart';

import 'outfit_fakes.dart';
import 'wardrobe_fakes.dart';

Future<void> _run(OutfitController controller) {
  final snapshot = fullSnapshot();
  return controller.run(
    video: snapshot.video!,
    live: snapshot.selectedLive!,
    culture: snapshot.culture,
  );
}

ApiException _error(String detail, int status) =>
    ApiException('{"detail":"$detail"}', statusCode: status);

void main() {
  test('提案 → 画像の順に進み、提案の服で画像を作る(spec 011 AC-9, AC-11)', () async {
    final suggestion = Completer<OutfitSuggestion>();
    final repo = FakeOutfitRepository(
      suggestResponder: () => suggestion.future,
    );
    final controller = OutfitController(repository: repo);
    addTearDown(controller.dispose);
    final stages = <OutfitStage>[];
    controller.addListener(() => stages.add(controller.stage));

    final running = _run(controller);
    expect(controller.stage, OutfitStage.suggesting);
    expect(controller.running, isTrue);
    expect(controller.startedAt, isNotNull);

    suggestion.complete(suggestionOf('晴れの日のライブコーデ'));
    await running;

    expect(stages, [
      OutfitStage.suggesting,
      OutfitStage.imaging,
      OutfitStage.done,
    ]);
    expect(repo.suggestCalls.single.live.liveName, '公演A');
    expect(repo.imageCalls, [
      ['shirt', 'jeans'],
    ]);
    expect(controller.suggestion?.title, '晴れの日のライブコーデ');
    expect(controller.image?.bytes, pngBytes);
    expect(controller.running, isFalse);
  });

  test('画像だけ失敗したら提案を残し、作り直せる(spec 011 AC-13)', () async {
    var attempts = 0;
    final repo = FakeOutfitRepository(
      imageResponder: (ids) async {
        if (++attempts == 1) throw _error('モデルが画像を返しませんでした。', 502);
        return OutfitImage(bytes: pngBytes, mimeType: 'image/png');
      },
    );
    final controller = OutfitController(repository: repo);
    addTearDown(controller.dispose);

    await _run(controller);

    expect(controller.stage, OutfitStage.done);
    expect(controller.suggestion, isNotNull);
    expect(controller.imageError, 'モデルが画像を返しませんでした。');

    final retrying = controller.retryImage();
    expect(controller.retryingImage, isTrue);
    expect(controller.imageError, isNull);
    await retrying;

    expect(controller.retryingImage, isFalse);
    expect(controller.image, isNotNull);
    expect(repo.suggestCalls, hasLength(1));
    expect(repo.imageCalls, hasLength(2));
  });

  test('提案が失敗したら理由を残して何もしていない状態に戻り、画像は作らない(spec 011 AC-13)', () async {
    final repo = FakeOutfitRepository(
      suggestResponder: () async =>
          throw _error('Gemini のクォータ(利用上限)を超えました。', 503),
    );
    final controller = OutfitController(repository: repo);
    addTearDown(controller.dispose);

    await _run(controller);

    expect(controller.stage, OutfitStage.idle);
    expect(controller.error, 'Gemini のクォータ(利用上限)を超えました。');
    expect(controller.suggestion, isNull);
    expect(repo.imageCalls, isEmpty);
  });

  test('キャンセルしたら、後から届いた結果は捨てる(spec 015 AC-9)', () async {
    final suggestion = Completer<OutfitSuggestion>();
    final repo = FakeOutfitRepository(
      suggestResponder: () => suggestion.future,
    );
    final controller = OutfitController(repository: repo);
    addTearDown(controller.dispose);

    final running = _run(controller);
    controller.cancel();
    expect(controller.stage, OutfitStage.idle);

    suggestion.complete(suggestionOf('届いた提案'));
    await running;

    expect(controller.stage, OutfitStage.idle);
    expect(controller.suggestion, isNull);
    expect(repo.imageCalls, isEmpty);
  });

  test('やり直すと前の結果は置き換わる(spec 011 AC-14)', () async {
    final titles = ['1 回目', '2 回目'];
    final repo = FakeOutfitRepository(
      suggestResponder: () async => suggestionOf(titles.removeAt(0)),
    );
    final controller = OutfitController(repository: repo);
    addTearDown(controller.dispose);

    await _run(controller);
    expect(controller.suggestion?.title, '1 回目');

    final second = _run(controller);
    expect(controller.suggestion, isNull);
    expect(controller.image, isNull);
    await second;

    expect(controller.suggestion?.title, '2 回目');
  });
}
