import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/core/theme.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/culture_vibe.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';

const _video = MvVideo(
  videoId: 'abc',
  url: 'https://www.youtube.com/watch?v=abc',
  artist: 'YOASOBI',
  songTitle: 'アイドル',
  titleParsed: true,
  title: 'YOASOBI「アイドル」',
  channelTitle: 'Ayase / YOASOBI',
);

CultureReport _report({
  List<String> styles = const [],
  List<String> colors = const [],
  bool identified = true,
}) => CultureReport(
  artist: 'YOASOBI',
  identified: identified,
  fashion: FashionInfo(styles: styles, colors: colors),
);

void main() {
  group('CultureVibe.from', () {
    test('動画・カルチャー情報が無い / 特定できないときは null', () {
      expect(CultureVibe.from(null, _report(styles: ['ガーリー'])), isNull);
      expect(CultureVibe.from(_video, null), isNull);
      expect(
        CultureVibe.from(_video, _report(styles: ['ガーリー'], identified: false)),
        isNull,
      );
    });

    test('スタイルと色を判定する', () {
      final vibe = CultureVibe.from(
        _video,
        _report(styles: ['ガーリー'], colors: ['ピンク', '水色']),
      )!;
      expect(vibe.effect, VibeEffect.sparkle);
      expect(vibe.accent, CultureVibe.colorOf('ピンク'));
      expect(vibe.accent2, CultureVibe.colorOf('水色'));
      expect(vibe.isNone, isFalse);
    });

    test('判定できない言葉だけなら「演出なし」', () {
      final vibe = CultureVibe.from(
        _video,
        _report(styles: ['エレガント'], colors: ['玉虫色']),
      )!;
      expect(vibe.isNone, isTrue);
      expect(vibe.effect, isNull);
      expect(vibe.accent, isNull);
    });
  });

  group('スタイルの判定', () {
    test('部分一致で判定する(英語・大文字・全角も)', () {
      expect(CultureVibe.matchEffect(['UKロック系']), VibeEffect.sparks);
      expect(CultureVibe.matchEffect(['Punk']), VibeEffect.sparks);
      expect(CultureVibe.matchEffect(['ＲＥＴＲＯ']), VibeEffect.petals);
      expect(CultureVibe.matchEffect(['サイバーパンク']), VibeEffect.neon);
      expect(CultureVibe.matchEffect(['ガーリーロック']), VibeEffect.sparkle);
      expect(CultureVibe.matchEffect(['ストリート']), VibeEffect.neon);
      expect(CultureVibe.matchEffect(['森ガール']), VibeEffect.petals);
    });

    test('先頭の言葉を優先する', () {
      expect(
        CultureVibe.matchEffect(['エレガント', 'ナチュラル', 'ロック']),
        VibeEffect.petals,
      );
    });

    test('当てはまらなければ null', () {
      expect(CultureVibe.matchEffect(const []), isNull);
      expect(CultureVibe.matchEffect(['モード', 'エレガント']), isNull);
    });
  });

  group('色の判定', () {
    test('長い名前を優先する', () {
      expect(
        CultureVibe.colorOf('ショッキングピンク'),
        isNot(CultureVibe.colorOf('ピンク')),
      );
      expect(CultureVibe.colorOf('淡い水色'), CultureVibe.colorOf('スカイブルー'));
      expect(CultureVibe.colorOf('Navy'), CultureVibe.colorOf('紺'));
    });

    test('白などの明るすぎる色と、重複を飛ばして最大 2 色', () {
      final colors = CultureVibe.matchColors([
        '白',
        'アイボリー',
        '黒',
        'ブラック',
        '赤',
        '青',
      ]);
      expect(colors, [CultureVibe.colorOf('黒'), CultureVibe.colorOf('赤')]);
    });

    test('辞書に無い色は無視する', () {
      expect(CultureVibe.colorOf('玉虫色'), isNull);
      expect(CultureVibe.matchColors(['玉虫色', '']), isEmpty);
    });
  });

  group('配色', () {
    test('判定できないときは標準の配色', () {
      expect(CultureVibe.paletteOf(null), AppPalette.standard);
      expect(CultureVibe.paletteOf(const CultureVibe()), AppPalette.standard);
    });

    test('標準の配色は今までの色と同じ', () {
      final theme = buildTheme();
      expect(theme.colorScheme.primary, AppColors.accent);
      expect(theme.colorScheme.secondary, AppColors.accent2);
      expect(theme.extension<AppPalette>(), AppPalette.standard);
    });

    test('差し色は白い文字に対して 4.5:1 以上', () {
      for (final name in ['黄', 'ミント', 'ピンク', 'ゴールド', 'ラベンダー', '水色']) {
        final palette = CultureVibe.paletteOf(
          CultureVibe(accent: CultureVibe.colorOf(name)),
        );
        expect(
          AppPalette.contrastWithWhite(palette.accent),
          greaterThanOrEqualTo(4.5),
          reason: name,
        );
        expect(
          AppPalette.contrastWithWhite(palette.accent2),
          greaterThanOrEqualTo(4.5),
          reason: name,
        );
        expect(palette.dark, isFalse);
      }
    });

    test('火花・ネオンは暗い背景', () {
      for (final effect in [VibeEffect.sparks, VibeEffect.neon]) {
        final palette = CultureVibe.paletteOf(
          CultureVibe(accent: const Color(0xFFD7263D), effect: effect),
        );
        expect(palette.dark, isTrue);
        expect(palette.onBackground, Colors.white);
        expect(palette.backgroundTop.computeLuminance(), lessThan(0.1));
      }
    });

    test('スタイルだけのときは演出の既定色', () {
      final palette = CultureVibe.paletteOf(
        const CultureVibe(effect: VibeEffect.petals),
      );
      expect(
        palette.accent,
        AppPalette.readableOnWhite(
          CultureVibe.effectDefaults[VibeEffect.petals]!,
        ),
      );
    });

    test('lerp で色が間を取る', () {
      final other = CultureVibe.paletteOf(
        const CultureVibe(effect: VibeEffect.neon),
      );
      final mid = AppPalette.standard.lerp(other, 0.5);
      expect(mid.accent, Color.lerp(AppColors.accent, other.accent, 0.5));
      expect(AppPalette.standard.lerp(other, 1), other);
    });
  });
}
