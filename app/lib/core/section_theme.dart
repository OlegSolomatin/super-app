import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/shared/tokens/pf_colors.dart';

/// Тематический Skin для раздела сайта.
///
/// Каждый раздел (trading, admin, music, video, etc.) определяет:
/// - accent — основной цвет (primary)
/// - onAccent — текст на accent
/// - displayName — название раздела
/// - icon — иконка для навигации
/// - description — краткое описание
class SectionTheme {
  final Color accent;
  final Color onAccent;
  final String displayName;
  final PhosphorIconData icon;
  final String description;

  const SectionTheme({
    required this.accent,
    required this.onAccent,
    required this.displayName,
    required this.icon,
    this.description = '',
  });

  /// Primary accent for focus rings, CTAs, active states
  Color get ring => accent;

  // ─── Predefined Sections ──────────────────────────────────────────────

  /// Главная страница — нейтральная (Linear vibe)
  static const home = SectionTheme(
    accent: PfColors.accentHome,
    onAccent: Colors.white,
    displayName: 'Главная',
    icon: PhosphorIconsFill.house,
    description: 'Панель управления',
  );

  /// Трейдинг — Binance yellow
  static const trading = SectionTheme(
    accent: PfColors.accentTrading,
    onAccent: Color(0xFF181A20),
    displayName: 'Трейдинг',
    icon: PhosphorIconsFill.chartBar,
    description: 'Торговые стратегии и сделки',
  );

  /// Админка / Агенты — Linear lavender
  static const admin = SectionTheme(
    accent: PfColors.accentAdmin,
    onAccent: Colors.white,
    displayName: 'Агенты',
    icon: PhosphorIconsFill.robot,
    description: 'Управление AI агентами',
  );

  /// Музыка — Spotify green
  static const music = SectionTheme(
    accent: PfColors.accentMusic,
    onAccent: Colors.white,
    displayName: 'Музыка',
    icon: PhosphorIconsFill.musicNotes,
    description: 'Медиатека',
  );

  /// Видео — YouTube red
  static const video = SectionTheme(
    accent: PfColors.accentVideo,
    onAccent: Colors.white,
    displayName: 'Видео',
    icon: PhosphorIconsFill.videoCamera,
    description: 'Видеотека',
  );

  /// Посты — Medium gray
  static const posts = SectionTheme(
    accent: PfColors.accentPosts,
    onAccent: Colors.white,
    displayName: 'Посты',
    icon: PhosphorIconsFill.fileText,
    description: 'Заметки и статьи',
  );

  /// Настройки — Stripe indigo
  static const settings = SectionTheme(
    accent: PfColors.accentSettings,
    onAccent: Colors.white,
    displayName: 'Настройки',
    icon: PhosphorIconsFill.gear,
    description: 'Профиль и конфигурация',
  );

  /// Логин — Stripe indigo (светлая тема)
  static const login = SectionTheme(
    accent: PfColors.accentLogin,
    onAccent: Colors.white,
    displayName: 'Вход',
    icon: PhosphorIconsFill.key,
    description: 'Авторизация',
  );

  /// Все разделы списком для навигации
  static const List<SectionTheme> all = [
    home,
    trading,
    music,
    video,
    posts,
    admin,
    settings,
  ];
}
