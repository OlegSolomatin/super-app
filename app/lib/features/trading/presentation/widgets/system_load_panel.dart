import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/features/trading/data/models/system_load.dart';
import 'package:app/features/trading/presentation/widgets/load_indicator_bar.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/pf_card.dart';

/// Панель индикаторов загрузки системы: CPU, RAM, API.
/// Показывается на странице трейдинга между блоком режимов и табами.
class SystemLoadPanel extends StatelessWidget {
  final SystemLoad load;

  const SystemLoadPanel({super.key, required this.load});

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);

    // Нормализуем RAM: шкала 0-10GB → 0-100%
    final ramPct = (load.ramGb / 10 * 100).clamp(0.0, 100.0);

    return PfCard(
      padding: const EdgeInsets.all(PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Text(
            'Загрузка системы',
            style: PfTypography.titleMd.copyWith(
              color: pc.foregroundC,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: PfSpacing.sm),
          // CPU
          LoadIndicatorBar(
            icon: PhosphorIconsFill.cpu,
            label: 'CPU',
            value: load.cpuPercent,
            displayValue: '${load.cpuPercent.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 8),
          // RAM
          LoadIndicatorBar(
            icon: PhosphorIconsFill.memory,
            label: 'RAM',
            value: ramPct,
            displayValue: '${load.ramGb.toStringAsFixed(1)}/10 GB',
          ),
          const SizedBox(height: 8),
          // API
          LoadIndicatorBar(
            icon: PhosphorIconsFill.wifiHigh,
            label: 'API',
            value: load.apiUsagePercent,
            displayValue: '${load.apiUsagePercent.toStringAsFixed(0)}%',
          ),
          // Предупреждения
          if (load.warnings.isNotEmpty) ...[
            const SizedBox(height: PfSpacing.sm),
            ...load.warnings.map((w) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: PhosphorIcon(
                      PhosphorIconsFill.warning,
                      size: 14,
                      color: const Color(0xFFF0B90B),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      w,
                      style: PfTypography.bodySm.copyWith(
                        color: const Color(0xFFF0B90B),
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}
