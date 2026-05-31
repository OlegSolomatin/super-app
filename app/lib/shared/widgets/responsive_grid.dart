import 'package:flutter/material.dart';
import 'responsive_layout.dart';

/// GridView that adapts its column count to screen width.
///
/// Last incomplete rows are always centered (not left-aligned like GridView).
class ResponsiveGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;
  final double runSpacing;
  final double? childAspectRatio;
  final EdgeInsets? padding;

  /// Column count per breakpoint.
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;

  const ResponsiveGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = 16,
    this.runSpacing = 16,
    this.childAspectRatio,
    this.padding,
    this.mobileColumns = 2,
    this.tabletColumns = 3,
    this.desktopColumns = 4,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final screenSize = ResponsiveLayout.screenOf(width);
        final crossAxisCount = switch (screenSize) {
          ScreenSize.mobile => mobileColumns,
          ScreenSize.tablet => tabletColumns,
          ScreenSize.desktop => desktopColumns,
        };

        final hp = padding?.horizontal ?? 0;
        final cardWidth =
            (width - hp - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final aspect = childAspectRatio ?? 1.1;
        final cardHeight = aspect > 0 ? cardWidth / aspect : cardWidth;

        return Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Wrap(
            spacing: spacing,
            runSpacing: runSpacing,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: List.generate(itemCount, (i) {
              return SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: itemBuilder(context, i),
              );
            }),
          ),
        );
      },
    );
  }
}

/// Wraps content in a horizontal [Wrap] for desktop or [Column] for mobile.
class ResponsiveWrap extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  const ResponsiveWrap({
    super.key,
    required this.children,
    this.spacing = 16,
    this.runSpacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);
    if (isWide) {
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: children,
      );
    }
    return Column(
      children: List.generate(children.length, (i) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: i < children.length - 1 ? runSpacing : 0),
          child: children[i],
        );
      }),
    );
  }
}
