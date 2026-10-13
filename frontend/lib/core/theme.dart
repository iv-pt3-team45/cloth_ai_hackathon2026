import 'package:flutter/material.dart';

/// アプリ全体の配色(参考 UI `tadasii/` と同じ。spec 015)。
///
/// 差し色(accent / accent2 / selected / bg)は MV に合わせて変わるため、画面では [AppPalette.of] から読む(spec 039)。
/// ここの値は標準の配色([AppPalette.standard])と、差し色以外の色(文字・枠・ok・ng)。
abstract final class AppColors {
  static const bg = Color(0xFFF6F3EF);
  static const surface = Colors.white;
  static const text = Color(0xFF1F1B24);
  static const muted = Color(0xFF6B6572);
  static const border = Color(0xFFE4DED6);
  static const accent = Color(0xFFD6334F);
  static const accent2 = Color(0xFF7A3CF0);
  static const ok = Color(0xFF1F8A5B);
  static const ng = Color(0xFFB8651B);
  static const soft = Color(0xFFF1EBE4);

  /// 選んだ候補の背景(薄い赤)
  static const selected = Color(0xFFFDEEF1);
}

/// 画面の差し色と背景(spec 039)。MV のカルチャー情報に合わせて切り替える。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.accent,
    required this.accent2,
    required this.selected,
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.onBackground,
    required this.onBackgroundMuted,
    this.dark = false,
  });

  /// 今までと同じ配色
  static const standard = AppPalette(
    accent: AppColors.accent,
    accent2: AppColors.accent2,
    selected: AppColors.selected,
    backgroundTop: AppColors.bg,
    backgroundBottom: AppColors.bg,
    onBackground: AppColors.text,
    onBackgroundMuted: AppColors.muted,
  );

  /// ボタン・番号の丸などの差し色(白い文字を載せても読める濃さ)
  final Color accent;

  /// 2 つ目の差し色(グラデーション・リンク)
  final Color accent2;

  /// 選んだ候補などの薄い地
  final Color selected;

  /// 画面の背景のグラデーション(上 → 下)
  final Color backgroundTop;
  final Color backgroundBottom;

  /// カードの外に置く文字の色
  final Color onBackground;
  final Color onBackgroundMuted;

  /// 暗い背景か
  final bool dark;

  /// 差し色 2 つから配色を作る。差し色は白い文字が読める濃さに調整する。
  factory AppPalette.fromAccents(
    Color accent,
    Color? accent2, {
    bool dark = false,
  }) {
    final main = readableOnWhite(accent);
    var second = readableOnWhite(accent2 ?? shiftHue(accent, 40));
    // 2 色が同じだとグラデーションにならないため、色相をずらす
    if (second == main) second = readableOnWhite(shiftHue(accent, 40));
    return AppPalette(
      accent: main,
      accent2: second,
      selected: Color.lerp(main, Colors.white, 0.92)!,
      backgroundTop: dark
          ? Color.lerp(const Color(0xFF1A1420), main, 0.15)!
          : Color.lerp(main, Colors.white, 0.85)!,
      backgroundBottom: dark
          ? Color.lerp(const Color(0xFF0E0B12), second, 0.12)!
          : Color.lerp(second, Colors.white, 0.95)!,
      onBackground: dark ? Colors.white : AppColors.text,
      onBackgroundMuted: dark ? Colors.white70 : AppColors.muted,
      dark: dark,
    );
  }

  /// 画面の配色(テーマに無ければ標準)
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? standard;

  /// 白い文字とのコントラストが 4.5:1 以上になるまで明度を下げる。
  static Color readableOnWhite(Color color) {
    var hsl = HSLColor.fromColor(color);
    while (contrastWithWhite(hsl.toColor()) < 4.5 && hsl.lightness > 0) {
      hsl = hsl.withLightness((hsl.lightness - 0.02).clamp(0, 1));
    }
    return hsl.toColor();
  }

  /// 白とのコントラスト比(WCAG)
  static double contrastWithWhite(Color color) =>
      1.05 / (color.computeLuminance() + 0.05);

  /// 色相を [degrees] 度ずらした色
  static Color shiftHue(Color color, double degrees) {
    final hsl = HSLColor.fromColor(color);
    // 無彩色(黒・灰)は色相をずらしても変わらないため、既定の 2 色目を使う
    if (hsl.saturation < 0.15) return AppColors.accent2;
    return hsl.withHue((hsl.hue + degrees) % 360).toColor();
  }

  @override
  AppPalette copyWith({
    Color? accent,
    Color? accent2,
    Color? selected,
    Color? backgroundTop,
    Color? backgroundBottom,
    Color? onBackground,
    Color? onBackgroundMuted,
    bool? dark,
  }) => AppPalette(
    accent: accent ?? this.accent,
    accent2: accent2 ?? this.accent2,
    selected: selected ?? this.selected,
    backgroundTop: backgroundTop ?? this.backgroundTop,
    backgroundBottom: backgroundBottom ?? this.backgroundBottom,
    onBackground: onBackground ?? this.onBackground,
    onBackgroundMuted: onBackgroundMuted ?? this.onBackgroundMuted,
    dark: dark ?? this.dark,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      backgroundTop: Color.lerp(backgroundTop, other.backgroundTop, t)!,
      backgroundBottom: Color.lerp(
        backgroundBottom,
        other.backgroundBottom,
        t,
      )!,
      onBackground: Color.lerp(onBackground, other.onBackground, t)!,
      onBackgroundMuted: Color.lerp(
        onBackgroundMuted,
        other.onBackgroundMuted,
        t,
      )!,
      dark: t < 0.5 ? dark : other.dark,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      other.accent == accent &&
      other.accent2 == accent2 &&
      other.selected == selected &&
      other.backgroundTop == backgroundTop &&
      other.backgroundBottom == backgroundBottom &&
      other.onBackground == onBackground &&
      other.onBackgroundMuted == onBackgroundMuted &&
      other.dark == dark;

  @override
  int get hashCode => Object.hash(
    accent,
    accent2,
    selected,
    backgroundTop,
    backgroundBottom,
    onBackground,
    onBackgroundMuted,
    dark,
  );
}

/// アプリ全体のテーマ(spec 015)。差し色は [palette] から作る(spec 039)。
ThemeData buildTheme({AppPalette palette = AppPalette.standard}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    primary: palette.accent,
    secondary: palette.accent2,
    surface: AppColors.surface,
    error: AppColors.accent,
  );
  const radius = BorderRadius.all(Radius.circular(12));
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    extensions: [palette],
    textTheme: Typography.blackMountainView.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
