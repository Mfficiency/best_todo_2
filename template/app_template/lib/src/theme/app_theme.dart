import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_settings.dart';

/// Builds the app's light and dark themes from [AppSettings]. Two families:
///
///  * **Standard** — Material 3 generated from [AppConfig.seedColor]. Change
///    that one colour to recolour the whole app.
///  * **Minimalist** — a monochrome ink-on-paper look: pure greys, flat
///    surfaces, no ink splashes, and selection shown with an underline instead
///    of a filled highlight. Works in both light and dark.
///
/// Lifted from the host app so the look-and-feel carries over verbatim.
class AppTheme {
  AppTheme._();

  static ThemeData light(AppSettings s) => s.minimalist
      ? minimalist(Brightness.light)
      : standard(Brightness.light);

  static ThemeData dark(AppSettings s) => s.minimalist
      ? minimalist(Brightness.dark)
      : standard(Brightness.dark);

  /// Material 3 theme seeded from [AppConfig.seedColor], keeping the exact seed
  /// as the primary so the brand colour never drifts.
  static ThemeData standard(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppConfig.seedColor,
        brightness: brightness,
      ).copyWith(primary: AppConfig.seedColor),
      useMaterial3: true,
    );
  }

  /// Monochrome ink-on-paper theme (see class docs).
  static ThemeData minimalist(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final paper = dark ? const Color(0xFF141414) : const Color(0xFFFAFAFA);
    final ink = dark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
    final faintInk = dark ? const Color(0xFFA3A3A3) : const Color(0xFF616161);
    final mist = dark ? const Color(0xFF262626) : const Color(0xFFEEEEEE);
    final line = dark ? const Color(0xFF3A3A3A) : const Color(0xFFDBDBDB);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: ink,
      onPrimary: paper,
      primaryContainer: mist,
      onPrimaryContainer: ink,
      secondary: faintInk,
      onSecondary: paper,
      secondaryContainer: mist,
      onSecondaryContainer: ink,
      tertiary: faintInk,
      onTertiary: paper,
      error: ink,
      onError: paper,
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: faintInk,
      surfaceContainerHighest: mist,
      outline: faintInk,
      outlineVariant: line,
      inverseSurface: ink,
      onInverseSurface: paper,
      inversePrimary: paper,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      splashFactory: NoSplash.splashFactory,
      dividerTheme: DividerThemeData(color: line),
      // Selected chips (e.g. the settings section chips) keep their quiet
      // outline and underline their label instead of filling with colour.
      chipTheme: ChipThemeData(
        selectedColor: Colors.transparent,
        showCheckmark: false,
        side: BorderSide(color: line),
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            color: ink,
            decoration: states.contains(WidgetState.selected)
                ? TextDecoration.underline
                : TextDecoration.none,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
