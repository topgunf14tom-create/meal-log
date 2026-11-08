import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E7D5B),
        brightness: brightness,
      ),
    );

class MacroColors {
  static const protein = Color(0xFFE57373);
  static const fat = Color(0xFFFFB74D);
  static const carbs = Color(0xFF64B5F6);
}
