import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/zt_app_config.dart';
import '../../config/zt_suite.dart';
import '../../core_providers.dart';

/// Spacing steps every app uses, so screens line up across the suite.
abstract final class ZtSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// One look for every Zero-Trust app: shared brand seed, shapes, surfaces
/// and type, with the app's accent (from [ZtSuite]) as the secondary colour.
abstract final class ZtTheme {
  /// Indigo, shared by the whole suite.
  static const Color brandSeed = Color(0xFF6366F1);

  static const double radius = 16;

  static ThemeData light({Color? accent}) =>
      fromScheme(_scheme(Brightness.light, accent));
  static ThemeData dark({Color? accent}) =>
      fromScheme(_scheme(Brightness.dark, accent));

  /// The app's accent: [ZtAppConfig.accent], else its colour in [ZtSuite].
  static Color? accentFor(ZtAppConfig config) =>
      config.accent ?? ZtSuite.byId(config.appId)?.accent;

  static ColorScheme _scheme(Brightness brightness, Color? accent) {
    final base =
        ColorScheme.fromSeed(seedColor: brandSeed, brightness: brightness);
    if (accent == null) return base;
    // The accent's tonal roles, so text on it keeps its contrast.
    final a = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
    return base.copyWith(
      secondary: a.primary,
      onSecondary: a.onPrimary,
      secondaryContainer: a.primaryContainer,
      onSecondaryContainer: a.onPrimaryContainer,
    );
  }

  /// The shared component styling over any [scheme], including the
  /// wallpaper colours of Material You.
  static ThemeData fromScheme(ColorScheme scheme) {
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: shape,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: shape,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius + 8)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }
}

/// The app's root theme in one place: brand or Material You colours (the
/// user's choice under Settings → Appearance), light/dark/system, all
/// remembered per install.
///
/// ```dart
/// ZtThemeBuilder(
///   builder: (context, theme, darkTheme, mode) => MaterialApp(
///     theme: theme, darkTheme: darkTheme, themeMode: mode, home: ...),
/// )
/// ```
class ZtThemeBuilder extends ConsumerWidget {
  const ZtThemeBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, ThemeData theme,
      ThemeData darkTheme, ThemeMode mode) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ZtTheme.accentFor(ref.watch(ztAppConfigProvider));
    final mode = ref.watch(themeModeProvider);
    final dynamic = ref.watch(ztDynamicColorProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic =
            dynamic && lightDynamic != null && darkDynamic != null;
        return builder(
          context,
          useDynamic
              ? ZtTheme.fromScheme(lightDynamic.harmonized())
              : ZtTheme.light(accent: accent),
          useDynamic
              ? ZtTheme.fromScheme(darkDynamic.harmonized())
              : ZtTheme.dark(accent: accent),
          mode,
        );
      },
    );
  }
}
