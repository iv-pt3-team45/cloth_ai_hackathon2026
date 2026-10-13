import 'dart:ui' show Color;

import '../../core/theme.dart';
import 'culture_models.dart';
import 'mv_models.dart';

/// 背景で流し続ける動きの種類(spec 039)。
enum VibeEffect {
  /// きらめき: 星とハートが舞い上がる
  sparkle,

  /// 火花: 火花が上がり、照明のように明滅する(暗い背景)
  sparks,

  /// 花びら: 花びらがゆっくり舞い落ちる
  petals,

  /// ネオン: 光の粒が線を描いて流れる(暗い背景)
  neon;

  /// 暗い背景にする演出か
  bool get dark => this == sparks || this == neon;
}

/// カルチャー情報から導き出す、画面の演出の設定(spec 039)。
///
/// 判定に使うのは `fashion.colors`(色の名前)と `fashion.styles`(スタイルの言葉)だけ。
/// Gemini の応答は言い回しが毎回少し違うため、言葉の部分一致で判定し、外れたら「演出なし」に倒す。
class CultureVibe {
  const CultureVibe({this.accent, this.accent2, this.effect});

  /// よく使う色から判定した差し色(判定できなければ null)
  final Color? accent;

  /// 2 色目(判定できなければ null)
  final Color? accent2;

  /// スタイルから判定した背景の動き(判定できなければ null)
  final VibeEffect? effect;

  /// 配色も背景の動きも判定できなかった
  bool get isNone => accent == null && effect == null;

  /// スタイルだけ判定できて色が取れないときの、演出ごとの既定の差し色
  static const effectDefaults = {
    VibeEffect.sparkle: Color(0xFFE0457B),
    VibeEffect.sparks: Color(0xFFE03A1E),
    VibeEffect.petals: Color(0xFFB5734A),
    VibeEffect.neon: Color(0xFF7A3CF0),
  };

  /// 画面の配色。判定できなかったもの(null・isNone)は標準のまま。
  static AppPalette paletteOf(CultureVibe? vibe) {
    if (vibe == null || vibe.isNone) return AppPalette.standard;
    final effect = vibe.effect;
    return AppPalette.fromAccents(
      vibe.accent ?? effectDefaults[effect]!,
      vibe.accent2,
      dark: effect?.dark ?? false,
    );
  }

  /// 動画と、アーティストを特定できたカルチャー情報があるときだけ判定する。それ以外は null。
  static CultureVibe? from(MvVideo? video, CultureReport? culture) {
    if (video == null || culture == null || !culture.identified) return null;
    final colors = matchColors(culture.fashion.colors);
    return CultureVibe(
      accent: colors.isEmpty ? null : colors.first,
      accent2: colors.length < 2 ? null : colors[1],
      effect: matchEffect(culture.fashion.styles),
    );
  }

  /// 色の名前の一覧から、差し色に使える色を先頭から最大 2 色返す。
  static List<Color> matchColors(List<String> names) {
    final result = <Color>[];
    for (final name in names) {
      final color = colorOf(name);
      if (color == null || _tooLight.contains(color)) continue;
      if (result.contains(color)) continue;
      result.add(color);
      if (result.length == 2) break;
    }
    return result;
  }

  /// 色の名前 1 つを色の値にする(辞書に無ければ null)。長い名前から先に照合する。
  static Color? colorOf(String name) {
    final text = _normalize(name);
    for (final (key, color) in _colorsByLength) {
      if (text.contains(key)) return color;
    }
    return null;
  }

  /// スタイルの言葉の一覧から、先頭の言葉を優先して演出を 1 つ返す(無ければ null)。
  ///
  /// 1 つの言葉に複数の演出の言葉が含まれるときは、長く一致したほうを使う(「サイバーパンク」→ ネオン)。
  static VibeEffect? matchEffect(List<String> styles) {
    for (final style in styles) {
      final text = _normalize(style);
      VibeEffect? best;
      var bestLength = 0;
      for (final (effect, words) in _effectWords) {
        for (final word in words) {
          if (word.length > bestLength && text.contains(word)) {
            best = effect;
            bestLength = word.length;
          }
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  /// 大文字小文字・全角半角の英数字の違いをなくす。
  static String _normalize(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      // 全角英数字(! 〜 ~)を半角にする
      buffer.writeCharCode(
        rune >= 0xFF01 && rune <= 0xFF5E ? rune - 0xFEE0 : rune,
      );
    }
    return buffer.toString().toLowerCase();
  }
}

const _white = Color(0xFFFFFFFF);
const _ivory = Color(0xFFF5F0E1);
const _beige = Color(0xFFD9C3A0);
const _cream = Color(0xFFF3E5AB);

/// 明るすぎて差し色にならない色(飛ばす)
const _tooLight = [_white, _ivory, _cream];

/// 色の名前の辞書(日本語・カタカナ・英語)。照合は小文字にした入力との部分一致。
const _colors = <(String, Color)>[
  ('ショッキングピンク', Color(0xFFE4007F)),
  ('ピンク', Color(0xFFE8618C)),
  ('桃色', Color(0xFFE8618C)),
  ('pink', Color(0xFFE8618C)),
  ('ワインレッド', Color(0xFF7B1E3A)),
  ('ボルドー', Color(0xFF6C1B30)),
  ('ワイン', Color(0xFF7B1E3A)),
  ('burgundy', Color(0xFF6C1B30)),
  ('赤', Color(0xFFD7263D)),
  ('レッド', Color(0xFFD7263D)),
  ('red', Color(0xFFD7263D)),
  ('オレンジ', Color(0xFFF08A24)),
  ('橙', Color(0xFFF08A24)),
  ('orange', Color(0xFFF08A24)),
  ('黄', Color(0xFFF2C230)),
  ('イエロー', Color(0xFFF2C230)),
  ('yellow', Color(0xFFF2C230)),
  ('ゴールド', Color(0xFFC9A227)),
  ('金', Color(0xFFC9A227)),
  ('gold', Color(0xFFC9A227)),
  ('ミント', Color(0xFF5CC8A8)),
  ('mint', Color(0xFF5CC8A8)),
  ('カーキ', Color(0xFF7A7444)),
  ('khaki', Color(0xFF7A7444)),
  ('オリーブ', Color(0xFF6B7A2E)),
  ('olive', Color(0xFF6B7A2E)),
  ('緑', Color(0xFF2E9E5B)),
  ('グリーン', Color(0xFF2E9E5B)),
  ('green', Color(0xFF2E9E5B)),
  ('ターコイズ', Color(0xFF1FB5B0)),
  ('turquoise', Color(0xFF1FB5B0)),
  ('水色', Color(0xFF5BB8E8)),
  ('スカイブルー', Color(0xFF5BB8E8)),
  ('ライトブルー', Color(0xFF5BB8E8)),
  ('sky', Color(0xFF5BB8E8)),
  ('紺', Color(0xFF1F2F5C)),
  ('ネイビー', Color(0xFF1F2F5C)),
  ('navy', Color(0xFF1F2F5C)),
  ('青', Color(0xFF2D6CDF)),
  ('ブルー', Color(0xFF2D6CDF)),
  ('blue', Color(0xFF2D6CDF)),
  ('ラベンダー', Color(0xFFA98BD9)),
  ('lavender', Color(0xFFA98BD9)),
  ('紫', Color(0xFF7A3CF0)),
  ('パープル', Color(0xFF7A3CF0)),
  ('バイオレット', Color(0xFF7A3CF0)),
  ('purple', Color(0xFF7A3CF0)),
  ('violet', Color(0xFF7A3CF0)),
  ('ブラウン', Color(0xFF7B4A2A)),
  ('茶', Color(0xFF7B4A2A)),
  ('brown', Color(0xFF7B4A2A)),
  ('ベージュ', _beige),
  ('beige', _beige),
  ('シルバー', Color(0xFF9EA3AD)),
  ('銀', Color(0xFF9EA3AD)),
  ('silver', Color(0xFF9EA3AD)),
  ('グレー', Color(0xFF7D7D85)),
  ('グレイ', Color(0xFF7D7D85)),
  ('灰', Color(0xFF7D7D85)),
  ('gray', Color(0xFF7D7D85)),
  ('grey', Color(0xFF7D7D85)),
  ('黒', Color(0xFF1F1B24)),
  ('ブラック', Color(0xFF1F1B24)),
  ('black', Color(0xFF1F1B24)),
  ('アイボリー', _ivory),
  ('ivory', _ivory),
  ('生成り', _ivory),
  ('クリーム', _cream),
  ('cream', _cream),
  ('白', _white),
  ('ホワイト', _white),
  ('white', _white),
];

/// 長い名前から先に照合する(「ショッキングピンク」「水色」を短い名前に負けさせない)
final _colorsByLength = [..._colors]
  ..sort((a, b) => b.$1.length.compareTo(a.$1.length));

/// スタイルの言葉 → 演出(design §4.1)。照合は小文字にした入力との部分一致。
const _effectWords = <(VibeEffect, List<String>)>[
  (
    VibeEffect.sparkle,
    [
      'ガーリー',
      'ポップ',
      'キュート',
      'アイドル',
      'かわいい',
      'カワイイ',
      'ロリータ',
      'girly',
      'pop',
      'cute',
      'idol',
    ],
  ),
  (
    VibeEffect.sparks,
    ['ロック', 'パンク', 'ハード', 'メタル', 'グランジ', 'rock', 'punk', 'metal', 'grunge'],
  ),
  (
    VibeEffect.petals,
    [
      'ナチュラル',
      'レトロ',
      'フォーク',
      '森ガール',
      'ヴィンテージ',
      'ビンテージ',
      '和',
      'natural',
      'retro',
      'folk',
      'vintage',
    ],
  ),
  (
    VibeEffect.neon,
    [
      'エレクトロ',
      'クラブ',
      'ダンス',
      'サイバー',
      'テクノ',
      'ストリート',
      'y2k',
      'electro',
      'club',
      'dance',
      'cyber',
      'techno',
    ],
  ),
];
