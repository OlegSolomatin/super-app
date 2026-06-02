import 'package:flutter/material.dart';

/// Скругления pfumiko design system.
///
/// Источник: DESIGN.md
class PfRadius {
  PfRadius._();

  static const double xs = 2;
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;
  static const double xxl = 16;
  static const double pill = 9999;

  // ─── Convenience BorderRadius ────────────────────────────────────
  static const BorderRadius borderRadiusXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius borderRadiusSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderRadiusMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderRadiusLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius borderRadiusXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius borderRadiusXxl = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius borderRadiusPill = BorderRadius.all(Radius.circular(pill));
}
