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
  final String size;

  const PfBadge({
    super.key,
    required this.label,
    this.variant = 'default',
    this.size = 'md',
  });

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
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
        bgColor = PfColors.accentAdmin.withValues(alpha: 0.15);
        fgColor = PfColors.accentAdmin;
      default:
        bgColor = pc.mutedC;
        fgColor = pc.mutedForegroundC;
    }

    final isSmall = size == 'sm';
    final vPad = isSmall ? 1.0 : 2.0;
    final hPad = isSmall ? 6.0 : 8.0;
    final fSize = isSmall ? 10.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: hPad,
        vertical: vPad,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: PfRadius.borderRadiusMd,
      ),
      child: Text(
        label,
        style: PfTypography.caption.copyWith(color: fgColor, fontSize: fSize),
      ),
    );
  }
}
