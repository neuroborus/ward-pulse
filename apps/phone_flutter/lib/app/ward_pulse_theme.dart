import 'package:flutter/material.dart';

/// WardPulse phone theme, shared by the app shell and widget tests.
final ThemeData wardPulseLightTheme = _theme(
  ColorScheme.fromSeed(
    seedColor: const Color(0xFF67E8D4),
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    primary: const Color(0xFF006B60),
    onPrimary: Colors.white,
    tertiary: const Color(0xFF715D00),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFFFE16B),
    onTertiaryContainer: const Color(0xFF221B00),
  ),
);

final ThemeData wardPulseDarkTheme = _theme(
  ColorScheme.fromSeed(
    seedColor: const Color(0xFF67E8D4),
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    primary: const Color(0xFF67E8D4),
    onPrimary: const Color(0xFF002F2A),
    primaryContainer: const Color(0xFF155B45),
    onPrimaryContainer: const Color(0xFFF4FBF8),
    tertiary: const Color(0xFFE6C349),
    onTertiary: const Color(0xFF3C2F00),
    tertiaryContainer: const Color(0xFF574500),
    onTertiaryContainer: const Color(0xFFFFE17A),
  ),
);

/// Cards stack flush and rounded on every surface, so screens only nest them.
ThemeData _theme(ColorScheme colorScheme) {
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    cardTheme: const CardThemeData(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
  );
}
