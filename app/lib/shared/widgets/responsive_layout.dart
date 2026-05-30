import 'package:flutter/material.dart';

/// Breakpoints for responsive layout
enum ScreenSize { mobile, tablet, desktop }

/// Provides screen size information and adaptive layout helpers.
class ResponsiveLayout extends StatelessWidget {
  final Widget Function(
    BuildContext context,
    ScreenSize screenSize,
    double width,
  ) builder;
  final double? maxContentWidth;

  const ResponsiveLayout({
    super.key,
    required this.builder,
    this.maxContentWidth = 1200,
  });

  /// Returns [ScreenSize] based on [width].
  static ScreenSize screenOf(double width) {
    if (width < 600) return ScreenSize.mobile;
    if (width < 1024) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  /// Convenience: get current screen size from context.
  static ScreenSize of(BuildContext context) {
    return screenOf(MediaQuery.of(context).size.width);
  }

  /// Returns true if the current screen is desktop or tablet.
  static bool isWide(BuildContext context) {
    return of(context) != ScreenSize.mobile;
  }

  /// Adaptive value: returns [mobile] on mobile, [other] on tablet/desktop.
  static T value<T>(BuildContext context, {required T mobile, required T other}) {
    return isWide(context) ? other : mobile;
  }

  /// Adaptive value with three tiers.
  static T select<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    switch (of(context)) {
      case ScreenSize.mobile:
        return mobile;
      case ScreenSize.tablet:
        return tablet ?? desktop;
      case ScreenSize.desktop:
        return desktop;
    }
  }

  /// Horizontal padding that scales with screen size.
  static EdgeInsets horizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return const EdgeInsets.symmetric(horizontal: 48);
    if (width > 600) return const EdgeInsets.symmetric(horizontal: 32);
    return const EdgeInsets.symmetric(horizontal: 16);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final screenSize = ScreenSize.values.firstWhere(
          (s) => width < _breakpoint(s),
          orElse: () => ScreenSize.desktop,
        );
        return builder(context, screenSize, width);
      },
    );
  }

  static double _breakpoint(ScreenSize size) {
    switch (size) {
      case ScreenSize.mobile:
        return 600;
      case ScreenSize.tablet:
        return 1024;
      case ScreenSize.desktop:
        return double.infinity;
    }
  }
}

/// Constrains content to a max width and centers it (desktop-optimised).
class ConstrainedContent extends StatelessWidget {
  final Widget child;
  final double? maxWidth;

  const ConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final max = maxWidth ?? 1200;
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }
}
