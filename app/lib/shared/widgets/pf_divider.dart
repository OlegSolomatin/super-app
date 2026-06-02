import 'package:flutter/material.dart';
import 'package:app/shared/tokens/pf_colors.dart';

/// Разделитель pfumiko design system.
///
/// Замена raw `Container(height: 1, color: ...)`.
/// Использует `--border` токен (#2B3139 для dark, #EAECEF для light).
class PfDivider extends StatelessWidget {
  final double thickness;
  final double indent;
  final double endIndent;
  final Color? color;

  const PfDivider({
    super.key,
    this.thickness = 1,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: thickness,
      margin: EdgeInsets.only(
        left: indent,
        right: endIndent,
      ),
      color: color ?? PfColors.border,
    );
  }
}

/// Вертикальный разделитель.
class PfVerticalDivider extends StatelessWidget {
  final double thickness;
  final double height;
  final Color? color;

  const PfVerticalDivider({
    super.key,
    this.thickness = 1,
    this.height = double.infinity,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: thickness,
      height: height,
      color: color ?? PfColors.border,
    );
  }
}
