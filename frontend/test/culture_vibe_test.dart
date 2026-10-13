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

    test('スタイルだけのときは演出の既定色(読みやすい濃さに調整した色)', () {
      final base = CultureVibe.effectDefaults[VibeEffect.petals]!;
      final palette = CultureVibe.paletteOf(
        const CultureVibe(effect: VibeEffect.petals),
      );
      // 色相は既定色のまま、明るさだけ下げる
      expect(
        HSLColor.fromColor(palette.accent).hue,
        closeTo(HSLColor.fromColor(base).hue, 1),
      );
      expect(
        HSLColor.fromColor(palette.accent).lightness,
        lessThanOrEqualTo(HSLColor.fromColor(base).lightness),
      );
    });

    group('文字と背景のコントラスト(spec 041 AC-4)', () {
      // 色の辞書の色(代表の名前)と、辞書に無い色(灰・黒・白に近い色)
      const names = [
        'ショッキングピンク', 'ピンク', 'ワインレッド', '赤', 'オレンジ', '黄', 'ゴールド', //
        'ミント', 'カーキ', 'オリーブ', '緑', 'ターコイズ', '水色', '紺', '青', //
        'ラベンダー', '紫', 'ブラウン', 'ベージュ', 'シルバー', 'グレー',
      ];
      final colors = [
        for (final n in names) CultureVibe.colorOf(n)!,
        const Color(0xFF000000),
        const Color(0xFF808080),
        const Color(0xFFFFFDF0),
      ];
      final effects = <VibeEffect?>[null, ...VibeEffect.values];

      void expectAtLeast(Color fg, Color bg, String reason) => expect(
        AppPalette.contrast(fg, bg),
        greaterThanOrEqualTo(4.5),
        reason: reason,
      );

      test('明るい配色: 差し色は白・選んだ項目の地・背景に、灰色の文字は背景に対して 4.5:1 以上', () {
        for (final effect in effects.where((e) => !(e?.dark ?? false))) {
          for (final a in colors) {
            for (final b in <Color?>[null, ...colors]) {
              final p = CultureVibe.paletteOf(
                CultureVibe(accent: a, accent2: b, effect: effect),
              );
              final why = '$effect $a $b';
              expect(p.dark, isFalse);
              for (final bg in [
                Colors.white,
                p.selected,
                p.backgroundTop,
                p.backgroundBottom,
              ]) {
                expectAtLeast(p.accent2, bg, 'accent2 $why');
              }
              for (final bg in [Colors.white, p.selected, p.backgroundTop]) {
                expectAtLeast(p.accent, bg, 'accent $why');
              }
              for (final bg in [p.backgroundTop, p.backgroundBottom]) {
                expectAtLeast(p.onBackground, bg, 'onBackground $why');
                expectAtLeast(p.onBackgroundMuted, bg, 'muted $why');
              }
            }
          }
        }
      });

      test('暗い配色: 背景の上の文字は背景に、差し色は白い文字に対して 4.5:1 以上', () {
        for (final effect in effects.where((e) => e?.dark ?? false)) {
          for (final a in colors) {
            for (final b in <Color?>[null, ...colors]) {
              final p = CultureVibe.paletteOf(
                CultureVibe(accent: a, accent2: b, effect: effect),
              );
              final why = '$effect $a $b';
              expect(p.dark, isTrue);
              for (final bg in [p.backgroundTop, p.backgroundBottom]) {
                expectAtLeast(p.onBackground, bg, 'onBackground $why');
                expectAtLeast(p.onBackgroundMuted, bg, 'muted $why');
              }
              expectAtLeast(Colors.white, p.accent, 'accent $why');
              expectAtLeast(Colors.white, p.accent2, 'accent2 $why');
            }
          }
        }
      });

      test('ensureContrast: 明るい背景では暗く、暗い背景では明るくし、足りていれば変えない', () {
        const pink = Color(0xFFFF9EC4);
        final onWhite = AppPalette.ensureContrast(pink, Colors.white);
        expectAtLeast(onWhite, Colors.white, 'white');
        expect(onWhite.computeLuminance(), lessThan(pink.computeLuminance()));

        const navy = Color(0xFF1B2A6B);
        const night = Color(0xFF120E18);
        final onDark = AppPalette.ensureContrast(navy, night);
        expectAtLeast(onDark, night, 'dark');
        expect(onDark.computeLuminance(), greaterThan(navy.computeLuminance()));

        expect(
          AppPalette.ensureContrast(AppColors.text, Colors.white),
          AppColors.text,
        );
      });

      test('contrast は WCAG の値(白と黒で 21、同じ色で 1)', () {
        expect(
          AppPalette.contrast(Colors.white, const Color(0xFF000000)),
          closeTo(21, 0.01),
        );
        expect(AppPalette.contrast(AppColors.accent, AppColors.accent), 1);
      });
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
