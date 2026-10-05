import 'package:flutter/material.dart';

/// アプリ全体の配色(参考 UI `tadasii/` と同じ。spec 015)。
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

/// アプリ全体のテーマ(spec 015)。
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    secondary: AppColors.accent2,
    surface: AppColors.surface,
    error: AppColors.accent,
  );
  const radius = BorderRadius.all(Radius.circular(12));
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
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
