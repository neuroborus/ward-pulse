import 'package:flutter/material.dart';

/// Gray-olive chrome — not a provider family color (see DESIGN_ASSETS.md).
const Color wardPulseOlive = Color(0xFF5F675C);
const Color wardPulseOliveLight = Color(0xFFA7B09E);
const Color wardPulseOnOliveDark = Color(0xFF1A1F1A);
const Color wardPulseOliveContainerLight = Color(0xFFE4E7DF);
const Color wardPulseOliveContainerDark = Color(0xFF3A4038);
const Color wardPulseOnOlive = Color(0xFFF4FBF8);

/// WardPulse phone theme, shared by the app shell and widget tests.
final ThemeData wardPulseLightTheme = _theme(
  ColorScheme.fromSeed(
    seedColor: wardPulseOlive,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    primary: wardPulseOlive,
    onPrimary: wardPulseOnOlive,
    primaryContainer: wardPulseOliveContainerLight,
    onPrimaryContainer: wardPulseOnOliveDark,
    tertiary: const Color(0xFF715D00),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFFFE16B),
    onTertiaryContainer: const Color(0xFF221B00),
  ),
);

final ThemeData wardPulseDarkTheme = _theme(
  ColorScheme.fromSeed(
    seedColor: wardPulseOlive,
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    primary: wardPulseOliveLight,
    onPrimary: wardPulseOnOliveDark,
    primaryContainer: wardPulseOliveContainerDark,
    onPrimaryContainer: wardPulseOnOlive,
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
