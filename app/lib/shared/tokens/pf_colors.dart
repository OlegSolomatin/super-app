import 'package:flutter/material.dart';

/// Цветовые токены pfumiko design system.
///
/// 3 слоя:
/// 1. Core цвета (raw hex)
/// 2. Semantic токены (background, card, border...)
/// 3. Section accent цвета (для Skin'ов)
///
/// Используй [PfColors.of(context)] для получения цветов под текущую тему.
/// Статические константы доступны но ВСЕГДА возвращают тёмную тему.
///
/// Источник: DESIGN.md
class PfColors {
  // ─── Dark theme core ──────────────────────────────────────────────────
  static const Color background = Color(0xFF0B0E11);
  static const Color foreground = Color(0xFFEAECEF);
  static const Color card = Color(0xFF1E2329);
  static const Color cardForeground = Color(0xFFEAECEF);
  static const Color surface = Color(0xFF2B3139);
  static const Color surfaceForeground = Color(0xFFEAECEF);
  static const Color muted = Color(0xFF2B3139);
  static const Color mutedForeground = Color(0xFF707A8A);
  static const Color border = Color(0xFF2B3139);
  static const Color input = Color(0xFF2B3139);
  static const Color sidebar = Color(0xFF010102);
  static const Color sidebarForeground = Color(0xFFD0D6E0);
  static const Color sidebarHairline = Color(0xFF23252A);
  static const Color success = Color(0xFF0ECB81);
  static const Color destructive = Color(0xFFF6465D);
  static const Color warning = Color(0xFFF0B90B);

  // ─── Light theme core ────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color foregroundLight = Color(0xFF181A20);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF0F0F0);
  static const Color mutedForegroundLight = Color(0xFF6B7280);
  static const Color borderLight = Color(0xFFEAECEF);
  static const Color sidebarLight = Color(0xFFFFFFFF);
  static const Color sidebarForegroundLight = Color(0xFF181A20);
  static const Color sidebarHairlineLight = Color(0xFFEAECEF);

  // ─── Section accent colors (skins) ───────────────────────────────────
  static const Color accentTrading = Color(0xFFFCD535);
  static const Color accentAdmin = Color(0xFF5E6AD2);
  static const Color accentMusic = Color(0xFF1DB954);
  static const Color accentVideo = Color(0xFFFF0000);
  static const Color accentPosts = Color(0xFF6B7280);
  static const Color accentSettings = Color(0xFF533AFD);
  static const Color accentLogin = Color(0xFF533AFD);
  static const Color accentHome = Color(0xFF5E6AD2);

  // ─── Chart colors ───────────────────────────────────────────────────
  static const Color chart1 = Color(0xFFFCD535);
  static const Color chart2 = Color(0xFF0ECB81);
  static const Color chart3 = Color(0xFF5E6AD2);
  static const Color chart4 = Color(0xFFF6465D);
  static const Color chart5 = Color(0xFF1DB954);

  // ─── Theme-aware accessor ───────────────────────────────────────────
  //
  // Используй PfColors.of(context).xxx для получения цвета под
  // текущую brightness (тёмная/светлая тема).
  //
  // Пример: PfColors.of(context).background

  late final Color backgroundC;
  late final Color foregroundC;
  late final Color cardC;
  late final Color cardForegroundC;
  late final Color surfaceC;
  late final Color surfaceForegroundC;
  late final Color mutedC;
  late final Color mutedForegroundC;
  late final Color borderC;
  late final Color inputC;
  late final Color successC;
  late final Color destructiveC;
  late final Color warningC;
  late final Color sidebarC;
  late final Color sidebarForegroundC;
  late final Color sidebarHairlineC;

  PfColors._({
    required this.backgroundC,
    required this.foregroundC,
    required this.cardC,
    required this.cardForegroundC,
    required this.surfaceC,
    required this.surfaceForegroundC,
    required this.mutedC,
    required this.mutedForegroundC,
    required this.borderC,
    required this.inputC,
    required this.successC,
    required this.destructiveC,
    required this.warningC,
    required this.sidebarC,
    required this.sidebarForegroundC,
    required this.sidebarHairlineC,
  });

  static final PfColors _dark = PfColors._(
    backgroundC: Color(0xFF0B0E11),
    foregroundC: Color(0xFFEAECEF),
    cardC: Color(0xFF1E2329),
    cardForegroundC: Color(0xFFEAECEF),
    surfaceC: Color(0xFF2B3139),
    surfaceForegroundC: Color(0xFFEAECEF),
    mutedC: Color(0xFF2B3139),
    mutedForegroundC: Color(0xFF707A8A),
    borderC: Color(0xFF2B3139),
    inputC: Color(0xFF2B3139),
    successC: Color(0xFF0ECB81),
    destructiveC: Color(0xFFF6465D),
    warningC: Color(0xFFF0B90B),
    sidebarC: Color(0xFF010102),
    sidebarForegroundC: Color(0xFFD0D6E0),
    sidebarHairlineC: Color(0xFF23252A),
  );

  static final PfColors _light = PfColors._(
    backgroundC: Color(0xFFF5F5F5),
    foregroundC: Color(0xFF181A20),
    cardC: Color(0xFFFFFFFF),
    cardForegroundC: Color(0xFF181A20),
    surfaceC: Color(0xFFF0F0F0),
    surfaceForegroundC: Color(0xFF181A20),
    mutedC: Color(0xFFF0F0F0),
    mutedForegroundC: Color(0xFF6B7280),
    borderC: Color(0xFFEAECEF),
    inputC: Color(0xFFEAECEF),
    successC: Color(0xFF0ECB81),
    destructiveC: Color(0xFFF6465D),
    warningC: Color(0xFFF0B90B),
    sidebarC: Color(0xFFFFFFFF),
    sidebarForegroundC: Color(0xFF181A20),
    sidebarHairlineC: Color(0xFFEAECEF),
  );

  /// Получить цвета под текущую тему.
  ///
  /// Пример: `PfColors.of(context).cardC` — цвет карточки для текущей темы.
  static PfColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.light ? _light : _dark;
  }
}
