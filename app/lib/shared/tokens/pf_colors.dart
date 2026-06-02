import 'package:flutter/material.dart';

/// Цветовые токены pfumiko design system.
///
/// 3 слоя:
/// 1. Core цвета (raw hex)
/// 2. Semantic токены (background, card, border...)
/// 3. Section accent цвета (для Skin'ов)
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
  static const Color borderLight = Color(0xFFEAECEF);

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
}
