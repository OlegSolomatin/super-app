import 'package:flutter/material.dart';

/// Отступы pfumiko design system.
///
/// Base unit: 4px
/// Источник: DESIGN.md
class PfSpacing {
  PfSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double section = 80;

  // ─── Convenience EdgeInsets ──────────────────────────────────────
  static const EdgeInsets allXs = EdgeInsets.all(xs);
  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allLg = EdgeInsets.all(lg);

  static const EdgeInsets symmetricHXs = EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets symmetricHSm =
      EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets symmetricHMd =
      EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets symmetricHLg =
      EdgeInsets.symmetric(horizontal: lg);

  static const EdgeInsets symmetricVXs = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets symmetricVSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets symmetricVMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets symmetricVLg = EdgeInsets.symmetric(vertical: lg);
}
