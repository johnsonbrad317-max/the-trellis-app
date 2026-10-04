import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Central Material 3 theme for The Trellis ("Parchment & Botanic").
///
/// EB Garamond — bundled in assets/fonts, never fetched at runtime — carries the
/// entire text theme, display through label.
class AppTheme {
  AppTheme._();

  /// The family name declared under `fonts:` in pubspec.yaml.
  static const fontFamily = 'EBGaramond';

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.forestGreen,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.forestGreen,
        secondary: AppColors.antiqueBrass,
        surface: AppColors.vellum,
        error: AppColors.terracotta,
      ),
    );

    final garamond = base.textTheme.apply(
      fontFamily: fontFamily,
      bodyColor: AppColors.forestGreen,
      displayColor: AppColors.forestGreen,
    );

    // EB Garamond has a small x-height, so Material's stock 28px headline
    // reads undersized — primary page headers (headlineMedium) are 32.
    final textTheme = garamond.copyWith(
      headlineMedium: garamond.headlineMedium?.copyWith(fontSize: 32, height: 1.15),
    );

    return base.copyWith(
      textTheme: textTheme,
      // No Material ripple or press-highlight anywhere: a tap on parchment
      // simply acts. (Every interactive widget in the app is a hand-built
      // GestureDetector; this also quiets the few structural Material hosts —
      // the app bar, drawer, bottom bar, text fields — that would otherwise
      // flash a splash.)
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      scaffoldBackgroundColor: AppColors.parchmentLight,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.forestGreen,
        titleTextStyle: textTheme.titleLarge,
      ),
      // The only Material components left in the app are structural hosts that
      // paint nothing of their own — Scaffold, the app bar, the drawer, the
      // bottom bar, and text fields — so this theme styles exactly those.
      // Every button, card, dialog, sheet, chip, toggle, checkbox, tab, icon,
      // picker and notice is hand-built (lib/widgets/bookplate_*.dart,
      // brass_*.dart, custom_toggle.dart), which is why there are no
      // component themes for them here.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.vellum,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.antiqueBrass.withValues(alpha: 0.55)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.antiqueBrass.withValues(alpha: 0.55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.antiqueBrass, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.vellum,
        selectedItemColor: AppColors.forestGreen,
        unselectedItemColor: AppColors.forestGreen.withValues(alpha: 0.45),
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: AppColors.vellum),
    );
  }
}
