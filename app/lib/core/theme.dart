import 'package:flutter/material.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/core/section_theme.dart';

/// Фабрика тем pfumiko design system.
///
/// Использует PfColors токены + SectionTheme для accent-цвета раздела.
/// Единый источник истины для всех визуальных стилей.
class AppTheme {
  // ─── Backward-compatible aliases (до редизайна виджетов) ──────────
  // Будут удалены после Фазы 2
  static Color get accentColor => PfColors.accentAdmin;
  static Color get bgColor => PfColors.background;
  static Color get surfaceColor => PfColors.surface;
  static Color get cardColor => PfColors.card;
  static Color get textPrimary => PfColors.foreground;
  static Color get textSecondary => PfColors.mutedForeground;
  static Color get lightBgColor => PfColors.backgroundLight;
  static Color get lightSurfaceColor => PfColors.cardLight;
  static Color get lightCardColor => PfColors.cardLight;
  static Color get lightTextPrimary => PfColors.foregroundLight;
  static Color get lightTextSecondary => PfColors.mutedForeground;

  // ─── Dark theme ──────────────────────────────────────────────────────
  static ThemeData darkTheme({SectionTheme section = SectionTheme.home}) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: PfColors.background,
      primaryColor: section.accent,

      colorScheme: ColorScheme.dark(
        primary: section.accent,
        onPrimary: section.onAccent,
        primaryContainer: section.accent.withValues(alpha: 0.15),
        secondary: PfColors.surface,
        onSecondary: PfColors.foreground,
        surface: PfColors.card,
        onSurface: PfColors.foreground,
        surfaceContainerHighest: PfColors.surface,
        error: PfColors.destructive,
        onError: Colors.white,
        outline: PfColors.border,
      ),

      // ─── AppBar ──────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: PfColors.background,
        foregroundColor: PfColors.foreground,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: PfTypography.titleLg.copyWith(color: PfColors.foreground),
        scrolledUnderElevation: 0,
      ),

      // ─── Card ────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: PfColors.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: PfRadius.borderRadiusXl,
          side: const BorderSide(color: PfColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ─── Input ───────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PfColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PfSpacing.md,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: PfRadius.borderRadiusLg,
          borderSide: const BorderSide(color: PfColors.input),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: PfRadius.borderRadiusLg,
          borderSide: const BorderSide(color: PfColors.input),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: PfRadius.borderRadiusLg,
          borderSide: BorderSide(color: section.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: PfRadius.borderRadiusLg,
          borderSide: const BorderSide(color: PfColors.destructive),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: PfRadius.borderRadiusLg,
          borderSide: const BorderSide(color: PfColors.destructive, width: 2),
        ),
        labelStyle: PfTypography.bodyMd.copyWith(color: PfColors.mutedForeground),
        hintStyle: PfTypography.bodyMd.copyWith(color: PfColors.mutedForeground),
      ),

      // ─── Buttons ─────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: section.accent,
          foregroundColor: section.onAccent,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: PfRadius.borderRadiusPill,
          ),
          textStyle: PfTypography.button,
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: section.accent,
          textStyle: PfTypography.button,
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.sm),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: PfColors.foreground,
          side: const BorderSide(color: PfColors.border),
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: PfRadius.borderRadiusLg,
          ),
          textStyle: PfTypography.button,
        ),
      ),

      // ─── Text ────────────────────────────────────────────────────────
      textTheme: TextTheme(
        headlineLarge: PfTypography.displayXl.copyWith(color: PfColors.foreground),
        headlineMedium: PfTypography.displayLg.copyWith(color: PfColors.foreground),
        headlineSmall: PfTypography.displayMd.copyWith(color: PfColors.foreground),
        titleLarge: PfTypography.titleLg.copyWith(color: PfColors.foreground),
        titleMedium: PfTypography.titleMd.copyWith(color: PfColors.foreground),
        bodyLarge: PfTypography.bodyLg.copyWith(color: PfColors.foreground),
        bodyMedium: PfTypography.bodyMd.copyWith(color: PfColors.foreground),
        bodySmall: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground),
        labelLarge: PfTypography.button.copyWith(color: PfColors.foreground),
        labelSmall: PfTypography.caption.copyWith(color: PfColors.mutedForeground),
      ),

      // ─── Divider ─────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: PfColors.border,
        thickness: 1,
        space: 0,
      ),

      // ─── Chip / Badge ───────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: PfColors.muted,
        labelStyle: PfTypography.caption.copyWith(color: PfColors.mutedForeground),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: PfRadius.borderRadiusMd,
        ),
        side: BorderSide.none,
      ),

      // ─── Progress Indicator ─────────────────────────────────────────
      // LinearProgressIndicator styling — use default theme params
      // Theme extension will be used in custom components (Phase 1)

      // ─── Dialog ─────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: PfColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: PfRadius.borderRadiusXl,
          side: const BorderSide(color: PfColors.border),
        ),
      ),

      // ─── Snackbar ────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: PfColors.card,
        contentTextStyle: PfTypography.bodyMd.copyWith(color: PfColors.foreground),
        shape: RoundedRectangleBorder(
          borderRadius: PfRadius.borderRadiusLg,
          side: const BorderSide(color: PfColors.border),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ─── Bottom Nav ────────────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: PfColors.background,
        selectedItemColor: section.accent,
        unselectedItemColor: PfColors.mutedForeground,
      ),

      // ─── Tab Bar ───────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: PfColors.foreground,
        unselectedLabelColor: PfColors.mutedForeground,
        indicatorColor: section.accent,
        labelStyle: PfTypography.button,
        unselectedLabelStyle: PfTypography.button,
      ),
    );
  }

  // ─── Light theme (login, forms) ──────────────────────────────────────
  static ThemeData lightTheme({SectionTheme section = SectionTheme.login}) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: PfColors.backgroundLight,
      primaryColor: section.accent,

      colorScheme: ColorScheme.light(
        primary: section.accent,
        onPrimary: section.onAccent,
        primaryContainer: section.accent.withValues(alpha: 0.12),
        secondary: PfColors.borderLight,
        onSecondary: PfColors.foregroundLight,
        surface: PfColors.cardLight,
        onSurface: PfColors.foregroundLight,
        error: PfColors.destructive,
        onError: Colors.white,
        outline: PfColors.borderLight,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: PfColors.cardLight,
        foregroundColor: PfColors.foregroundLight,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),

      cardTheme: CardThemeData(
        color: PfColors.cardLight,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: PfRadius.borderRadiusXl,
          side: const BorderSide(color: PfColors.borderLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: section.accent,
          foregroundColor: section.onAccent,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: PfRadius.borderRadiusPill,
          ),
          textStyle: PfTypography.button,
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PfColors.cardLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PfSpacing.md,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: PfRadius.borderRadiusLg,
          borderSide: const BorderSide(color: PfColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: PfRadius.borderRadiusLg,
          borderSide: const BorderSide(color: PfColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: PfRadius.borderRadiusLg,
          borderSide: BorderSide(color: section.accent, width: 2),
        ),
        labelStyle: PfTypography.bodyMd.copyWith(color: PfColors.mutedForeground),
        hintStyle: PfTypography.bodyMd.copyWith(color: PfColors.mutedForeground),
      ),

      textTheme: TextTheme(
        headlineLarge: PfTypography.displayXl.copyWith(color: PfColors.foregroundLight),
        headlineMedium: PfTypography.displayLg.copyWith(color: PfColors.foregroundLight),
        headlineSmall: PfTypography.displayMd.copyWith(color: PfColors.foregroundLight),
        titleLarge: PfTypography.titleLg.copyWith(color: PfColors.foregroundLight),
        titleMedium: PfTypography.titleMd.copyWith(color: PfColors.foregroundLight),
        bodyLarge: PfTypography.bodyLg.copyWith(color: PfColors.foregroundLight),
        bodyMedium: PfTypography.bodyMd.copyWith(color: PfColors.foregroundLight),
        bodySmall: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground),
        labelLarge: PfTypography.button.copyWith(color: PfColors.foregroundLight),
        labelSmall: PfTypography.caption.copyWith(color: PfColors.mutedForeground),
      ),

      dividerTheme: const DividerThemeData(
        color: PfColors.borderLight,
        thickness: 1,
        space: 0,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: PfColors.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: PfRadius.borderRadiusXl,
          side: const BorderSide(color: PfColors.borderLight),
        ),
      ),
    );
  }

  // ─── Convenience: get theme by mode + section ─────────────────────
  static ThemeData of({
    required ThemeMode mode,
    SectionTheme section = SectionTheme.home,
  }) {
    switch (mode) {
      case ThemeMode.light:
        return lightTheme(section: section);
      case ThemeMode.dark:
        return darkTheme(section: section);
      case ThemeMode.system:
        // WidgetsBinding.instance.window.platformBrightness недоступен
        // в изолированном контексте — используй MediaQuery в рантайме
        return darkTheme(section: section);
    }
  }
}
