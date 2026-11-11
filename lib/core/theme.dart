import 'package:flutter/material.dart';

/// 「キッチンスケール」テーマ：石の灰緑の地に墨の文字、液晶の緑灰（量りの表示部）をひとつだけ使う。
/// 文字は同梱の Zen Kaku Gothic New（日本語・英数字とも）。
class AppColors {
  /// 地（量りの筐体）
  static const body = Color(0xFFE6EAE4);

  /// 面（少し明るい）
  static const card = Color(0xFFEEF1EC);

  /// 入力欄・押せる面
  static const muted = Color(0xFFDCE1D9);

  /// 罫線
  static const border = Color(0xFFC4CBC2);

  /// 墨（文字・強い線・主ボタン）
  static const text = Color(0xFF1E2320);
  static const sub = Color(0xFF5C665F);
  static const faint = Color(0xFF8A938C);
  static const accent = text;
  static const onAccent = card;

  /// 液晶表示部
  static const lcd = Color(0xFFB7C4A6);
  static const lcdInk = Color(0xFF1F2B1C);
  static const lcdSub = Color(0xFF3E4B39);

  static const success = Color(0xFF4E7A3A);
  static const warning = Color(0xFFA8691F);
  static const error = Color(0xFFB0412C);
  static const info = Color(0xFF2F5D8A);
  static const over = error;
}

const _radiusElement = 6.0;
const _radiusContainer = 10.0;
const _font = 'ZenKaku';

ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    primaryContainer: AppColors.lcd,
    onPrimaryContainer: AppColors.lcdInk,
    secondary: AppColors.info,
    onSecondary: AppColors.card,
    secondaryContainer: AppColors.muted,
    onSecondaryContainer: AppColors.text,
    tertiary: AppColors.success,
    onTertiary: AppColors.card,
    error: AppColors.error,
    onError: AppColors.card,
    errorContainer: Color(0xFFF0D9D2),
    onErrorContainer: AppColors.error,
    surface: AppColors.body,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.sub,
    surfaceContainerLowest: AppColors.card,
    surfaceContainerLow: AppColors.card,
    surfaceContainer: AppColors.card,
    surfaceContainerHigh: AppColors.muted,
    surfaceContainerHighest: AppColors.muted,
    outline: AppColors.faint,
    outlineVariant: AppColors.border,
    inverseSurface: AppColors.text,
    onInverseSurface: AppColors.card,
    inversePrimary: AppColors.lcd,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: _font);
  final element = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusElement));
  const pill = StadiumBorder();

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
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
    ),
    // カードは影なし・細い罫線の面。中身の区切りは罫線で表す
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
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.sub),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.lcd,
      indicatorShape: element,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? AppColors.lcdInk : AppColors.sub,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: _font,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.text : AppColors.sub,
          )),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.text,
      foregroundColor: AppColors.card,
      elevation: 0,
      highlightElevation: 0,
      shape: pill,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        backgroundColor: AppColors.text,
        foregroundColor: AppColors.card,
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.text),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.text)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(element),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.text)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.lcd : null),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.lcdInk : AppColors.text),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: element,
      side: const BorderSide(color: AppColors.border),
      backgroundColor: AppColors.card,
      selectedColor: AppColors.lcd,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusElement),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusElement),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusElement),
        borderSide: const BorderSide(color: AppColors.text, width: 1.5),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.text,
      linearTrackColor: AppColors.muted,
      circularTrackColor: AppColors.muted,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.text : AppColors.muted),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.lcd : AppColors.faint),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.text : null),
      checkColor: const WidgetStatePropertyAll(AppColors.lcd),
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
      backgroundColor: AppColors.text,
      contentTextStyle: TextStyle(fontFamily: _font, color: AppColors.card),
      actionTextColor: AppColors.lcd,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class MacroColors {
  static const protein = AppColors.info;
  static const fat = AppColors.warning;
  static const carbs = AppColors.success;
}

/// 液晶表示風の数字（残りkcalなど、画面で一番読ませたい数字だけに使う）
const lcdNumberStyle = TextStyle(
  fontFamily: _font,
  fontWeight: FontWeight.w700,
  color: AppColors.lcdInk,
  height: 1,
  letterSpacing: 1.5,
  fontFeatures: [FontFeature.tabularFigures()],
);
