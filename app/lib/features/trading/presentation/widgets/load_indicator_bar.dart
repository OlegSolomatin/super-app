import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';

/// Горизонтальный индикатор загрузки (CPU, RAM, API).
///
/// Цвет прогресса:
/// - 0-60%  → PfColors.success   (#0ECB81)
/// - 60-80% → Color(0xFFF0B90B)  (warning yellow)
/// - 80-100% → PfColors.destructive (#F6465D)
class LoadIndicatorBar extends StatelessWidget {
  final String label;
  final double value; // 0-100
  final String displayValue;
  final PhosphorIconData icon;

  const LoadIndicatorBar({
    super.key,
    required this.label,
    required this.value,
    required this.displayValue,
    required this.icon,
  });

  Color _progressColor(double pct) {
    if (pct >= 80) return PfColors.destructive;
    if (pct >= 60) return const Color(0xFFF0B90B);
    return PfColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
    final color = _progressColor(value);

    return Row(
      children: [
        // Icon
        PhosphorIcon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        // Label
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: PfTypography.bodySm.copyWith(
              color: pc.foregroundC,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Progress bar
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                height: 8,
                decoration: BoxDecoration(
                  color: pc.surfaceC,
                  borderRadius: PfRadius.borderRadiusPill,
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (value / 100).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: PfRadius.borderRadiusPill,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        // Value
        Text(
          displayValue,
          style: PfTypography.bodySm.copyWith(
            color: pc.foregroundC,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
