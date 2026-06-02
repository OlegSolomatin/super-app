import 'package:flutter/material.dart';

/// Типографические токены pfumiko design system.
///
/// Шрифт: Inter (основной), JetBrains Mono (цифры/цены)
/// Источник: DESIGN.md
class PfTypography {
  PfTypography._();

  // ─── Display ─────────────────────────────────────────────────────────
  static const TextStyle displayXl = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -1.5,
  );
  static const TextStyle displayLg = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w600,
    height: 1.15,
    letterSpacing: -1.0,
  );
  static const TextStyle displayMd = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.5,
  );

  // ─── Titles ─────────────────────────────────────────────────────────
  static const TextStyle titleLg = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  static const TextStyle titleMd = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // ─── Body ─────────────────────────────────────────────────────────
  static const TextStyle bodyLg = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const TextStyle bodyMd = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const TextStyle bodySm = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // ─── Caption & Button ─────────────────────────────────────────────
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.0,
  );

  // ─── Numbers (JetBrains Mono) ────────────────────────────────────
  static const TextStyle number = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
  static const TextStyle numberDisplay = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: 40,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -1.0,
  );
}
