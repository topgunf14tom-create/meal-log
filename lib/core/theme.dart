import 'package:flutter/material.dart';

/// ダークテーマ（Astryx の Gothic テーマの色・角丸を Flutter に移したもの）。
/// 文字は同梱の Fustat（英数字）。日本語は端末のフォントで表示される。
class AppColors {
  static const body = Color(0xFF101314);
  static const card = Color(0xFF191D20);
  static const muted = Color(0xFF24292D);
  static const border = Color(0xFF2A3034);
  static const text = Color(0xFFE8F1F6);
  static const sub = Color(0xFF96A0AB);
  static const accent = Color(0xFFE8F1F6);
  static const onAccent = Color(0xFF101314);
  static const success = Color(0xFFB3C79A);
  static const warning = Color(0xFFD3C490);
  static const error = Color(0xFFE0A49C);
  static const info = Color(0xFF8AA1D8);
  static const over = Color(0xFFE0A46A);
}

const _radiusElement = 8.0;
const _radiusContainer = 12.0;

ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    primaryContainer: AppColors.muted,
    onPrimaryContainer: AppColors.text,
    secondary: AppColors.info,
    onSecondary: AppColors.onAccent,
    secondaryContainer: AppColors.muted,
    onSecondaryContainer: AppColors.text,
    tertiary: AppColors.success,
    onTertiary: AppColors.onAccent,
    error: AppColors.error,
    onError: AppColors.onAccent,
    errorContainer: Color(0xFF3A2523),
    onErrorContainer: AppColors.error,
    surface: AppColors.body,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.sub,
    surfaceContainerLowest: AppColors.body,
    surfaceContainerLow: AppColors.card,
    surfaceContainer: AppColors.card,
    surfaceContainerHigh: AppColors.muted,
    surfaceContainerHighest: AppColors.muted,
    outline: Color(0xFF4A535A),
    outlineVariant: AppColors.border,
    inverseSurface: AppColors.text,
    onInverseSurface: AppColors.body,
    inversePrimary: AppColors.body,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Fustat');
  final element = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusElement));

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.body,
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.body,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Fustat',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radiusContainer),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.sub),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accent,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 26,
            color: s.contains(WidgetState.selected) ? AppColors.onAccent : AppColors.sub,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: 'Fustat',
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.text : AppColors.sub,
          )),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
      elevation: 2,
      shape: StadiumBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: element)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: element,
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.text)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(element),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: element,
      side: const BorderSide(color: AppColors.border),
      backgroundColor: AppColors.card,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusElement),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusElement),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusElement),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.muted,
      circularTrackColor: AppColors.muted,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusContainer)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.muted,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class MacroColors {
  static const protein = AppColors.info;
  static const fat = AppColors.warning;
  static const carbs = AppColors.success;
}
