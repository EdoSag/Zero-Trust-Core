import 'package:flutter/material.dart';

/// One look for every Zero-Trust app: shared brand seed, shared shapes and
/// surfaces, optional per-app accent as the secondary colour.
abstract final class ZtTheme {
  /// Indigo from Zero-Trust Fitness, the most finished app today.
  static const Color brandSeed = Color(0xFF6366F1);

  static const double radius = 16;

  static ThemeData light({Color? accent}) => _build(Brightness.light, accent);
  static ThemeData dark({Color? accent}) => _build(Brightness.dark, accent);

  static ThemeData _build(Brightness brightness, Color? accent) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandSeed,
      brightness: brightness,
      secondary: accent,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: shape,
        color: scheme.surfaceContainerLow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
        filled: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: shape,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }
}
