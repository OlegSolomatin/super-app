import 'package:flutter/material.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';

/// Badge pfumiko design system.
///
/// Variants:
/// - `default` — нейтральный (серый)
/// - `success` — зелёный (активно, выполнено)
/// - `destructive` — красный (ошибка, стоп)
/// - `warning` — жёлтый (предупреждение, пауза)
/// - `info` — синий/акцентный (информация)
class PfBadge extends StatelessWidget {
  final String label;
  final String variant;

  const PfBadge({
    super.key,
    required this.label,
    this.variant = 'default',
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color fgColor;

    switch (variant) {
      case 'success':
        bgColor = PfColors.success;
        fgColor = Colors.white;
      case 'destructive':
        bgColor = PfColors.destructive;
        fgColor = Colors.white;
      case 'warning':
        bgColor = PfColors.warning;
        fgColor = const Color(0xFF181A20);
      case 'info':
        bgColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.15);
        fgColor = Theme.of(context).colorScheme.primary;
      default:
        bgColor = PfColors.muted;
        fgColor = PfColors.mutedForeground;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PfSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: PfRadius.borderRadiusMd,
      ),
      child: Text(
        label,
        style: PfTypography.caption.copyWith(color: fgColor),
      ),
    );
  }
}
