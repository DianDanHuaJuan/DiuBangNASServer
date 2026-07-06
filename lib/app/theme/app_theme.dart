import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFFF97316);
  static const Color accentColor = Color(0xFF006E2F);
  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFF97316);
  static const Color errorColor = Color(0xFFBA1A1A);
  static const Color infoColor = Color(0xFF0B1C30);

  static const Color diskIconColor = accentColor;
  static const Color memoryIconColor = primaryColor;
  static const Color networkIconColor = successColor;
  static const Color temperatureIconColor = Color(0xFF9E4036);

  static const Color lightBackground = Color(0xFFF8F9FF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardForeground = Color(0xFF0B1C30);
  static const Color lightLabel = Color(0xFF3D4A3D);
  static const Color lightDivider = Color(0xFFBCCBB9);
  static const Color lightSecondaryText = Color(0xFF6D7B6C);
  static const Color surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color surfaceContainer = Color(0xFFE5EEFF);
  static const Color surfaceContainerHigh = Color(0xFFDCE9FF);
  static const Color surfaceContainerHighest = Color(0xFFD3E4FE);
  static const Color surfaceBright = Color(0xFFF8F9FF);
  static const Color successContainer = Color(0xFFE8F7EE);
  static const Color warningContainer = Color(0xFFFFF1E8);
  static const Color errorContainer = Color(0xFFFFDAD6);

  static const Color darkBackground = Color(0xFF111111);
  static const Color darkCard = Color(0xFF1A1A1A);
  static const Color darkCardForeground = Color(0xFFFFFFFF);
  static const Color darkLabel = Color(0xFFB8B9B6);
  static const Color darkDivider = Color(0xFF2E2E2E);
  static const Color darkSecondaryText = Color(0xFF999999);

  static const String _fontFamily = 'NotoSansSC';

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      fontFamily: _fontFamily,
      fontFamilyFallback: const [_fontFamily, 'Microsoft YaHei', 'PingFang SC', 'SimHei', 'sans-serif'],
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: accentColor,
        surface: lightCard,
        onSurface: lightCardForeground,
        outline: lightDivider,
        error: errorColor,
      ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: lightCard,
        foregroundColor: lightCardForeground,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightDivider, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightCardForeground,
          side: const BorderSide(color: lightDivider, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightCard,
        labelStyle: const TextStyle(color: lightSecondaryText, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lightDivider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lightDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: successColor),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lightCardForeground,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dividerColor: lightDivider,
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      fontFamily: _fontFamily,
      fontFamilyFallback: const [_fontFamily, 'Microsoft YaHei', 'PingFang SC', 'SimHei', 'sans-serif'],
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: accentColor,
        surface: darkCard,
        onSurface: darkCardForeground,
        error: errorColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkCard,
        foregroundColor: darkCardForeground,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkDivider, width: 1),
        ),
      ),
    );
  }
}
