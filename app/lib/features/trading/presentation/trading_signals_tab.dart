import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/pf_card.dart';
import 'package:app/shared/widgets/pf_badge.dart';
import 'package:app/shared/widgets/pf_button.dart';
import 'package:app/shared/widgets/pf_skeleton.dart';
import 'package:app/features/trading/data/models/trading_signal.dart';
import 'package:app/features/trading/data/trading_repository.dart';

/// Tab showing live trading signals from Telegram screener channels.
class TradingSignalsTab extends StatefulWidget {
  final TradingRepository repository;

  const TradingSignalsTab({super.key, required this.repository});

  @override
  State<TradingSignalsTab> createState() => _TradingSignalsTabState();
}

class _TradingSignalsTabState extends State<TradingSignalsTab> {
  List<TradingSignal> _signals = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadSignals();
    // Poll every 5 seconds for live updates
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadSignals();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSignals() async {
    try {
      final signals = await widget.repository.getSignalsLive(limit: 50);
      if (mounted) {
        setState(() {
          _signals = signals;
          _loading = false;
        });
      }
    } catch (_) {
      // Fallback to DB signals if Redis is empty
      try {
        final signals = await widget.repository.getSignals(limit: 50);
        if (mounted) {
          setState(() {
            _signals = signals;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);

    if (_loading) {
      return _buildSkeleton();
    }

    if (_signals.isEmpty) {
      return _buildEmpty(pc);
    }

    return RefreshIndicator(
      onRefresh: _loadSignals,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
            PfSpacing.lg, PfSpacing.sm, PfSpacing.lg, PfSpacing.lg),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _signals.length,
        itemBuilder: (context, index) {
          final signal = _signals[index];
          return _SignalCard(signal: signal, repository: widget.repository);
        },
      ),
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: List.generate(4, (_) => const Padding(
        padding: EdgeInsets.fromLTRB(0, 4, 0, 4),
        child: PfSkeleton(
          height: 140,
          width: double.infinity,
          borderRadius: 12,
        ),
      )),
    );
  }

  Widget _buildEmpty(PfColors pc) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(
            PhosphorIconsFill.radio,
            size: 48,
            color: pc.mutedForegroundC.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Нет сигналов',
            style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC),
          ),
          const SizedBox(height: 4),
          Text(
            'Ждём новые сигналы из Telegram-каналов...',
            style: PfTypography.bodySm.copyWith(
                color: pc.mutedForegroundC.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 16),
          PfButton(
            label: 'Обновить',
            icon: PhosphorIconsFill.arrowClockwise,
            onPressed: () {
              setState(() => _loading = true);
              _loadSignals();
            },
          ),
        ],
      ),
    );
  }
}

/// Card widget for a single trading signal.
class _SignalCard extends StatelessWidget {
  final TradingSignal signal;
  final TradingRepository repository;

  const _SignalCard({
    required this.signal,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: PfSpacing.xs),
      child: PfCard(
        onTap: () => _showSignalDetail(context),
        padding: const EdgeInsets.all(PfSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: emoji + pair + time + channel badge ──
            Row(
              children: [
                Text(
                  '${signal.typeEmoji} ${signal.pair}',
                  style: PfTypography.titleMd.copyWith(
                    color: pc.foregroundC,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  signal.timeAgo,
                  style: PfTypography.caption.copyWith(
                    color: pc.mutedForegroundC,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // ── Exchange + type ──
            Row(
              children: [
                PfBadge(
                  label: signal.exchange,
                  variant: 'info',
                ),
                const SizedBox(width: 6),
                PfBadge(
                  label: signal.typeLabel,
                  variant: 'default',
                ),
                if (signal.mappedExchangeFallback != null) ...[
                  const SizedBox(width: 6),
                  PfBadge(
                    label: '→ ${signal.mappedExchangeFallback!.toUpperCase()}',
                    variant: 'success',
                  ),
                ],
              ],
            ),

            // ── Available exchanges ──
            if (signal.mappedAvailableExchanges != null &&
                signal.mappedAvailableExchanges!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: signal.mappedAvailableExchanges!.entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: PfBadge(
                            label: '${e.key.toUpperCase()} ${e.value ? "✅" : "❌"}',
                            variant: e.value ? 'success' : 'destructive',
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),

            // ── Metrics row ──
            Row(
              children: [
                if (signal.priceRange != null) ...[
                  _SignalMetric(
                    label: 'Range',
                    value: '${signal.priceRange!.toStringAsFixed(1)}%',
                    pc: pc,
                  ),
                  const SizedBox(width: 12),
                ],
                if (signal.vol10m != null) ...[
                  _SignalMetric(
                    label: 'Vol 10m',
                    value: _formatVolume(signal.vol10m!),
                    pc: pc,
                  ),
                  const SizedBox(width: 12),
                ],
                if (signal.slope != null) ...[
                  _SignalMetric(
                    label: 'Slope',
                    value: signal.slope!.toStringAsFixed(1),
                    pc: pc,
                  ),
                ],
                if (signal.topRatio != null && signal.botRatio != null) ...[
                  _SignalMetric(
                    label: 'T/B',
                    value:
                        '${signal.topRatio!.toStringAsFixed(2)}/${signal.botRatio!.toStringAsFixed(2)}',
                    pc: pc,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // ── Strategy recommendation ──
            if (signal.mappedStrategy != null) ...[
              Container(
                padding: const EdgeInsets.all(PfSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: PfRadius.borderRadiusSm,
                ),
                child: Row(
                  children: [
                    PhosphorIcon(
                      PhosphorIconsFill.target,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${signal.mappedStrategy} (${signal.engineLabel})',
                        style: PfTypography.caption.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (signal.confidence != null)
                      Text(
                        '${(signal.confidence! * 100).toInt()}%',
                        style: PfTypography.caption.copyWith(
                          color: theme.colorScheme.primary.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            // ── Action buttons ──
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PfButton(
                    label: '🚀 Запуск',
                    icon: PhosphorIconsFill.play,
                    size: 'sm',
                    variant: 'primary',
                    onPressed: () => _startRun(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PfButton(
                    label: '⚙️ Визард',
                    icon: PhosphorIconsFill.gear,
                    size: 'sm',
                    variant: 'secondary',
                    onPressed: () {
                      context.go('/trading/orderbook-wizard',
                          extra: {'pair': signal.pair});
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startRun(BuildContext context) async {
    if (signal.mappedStrategy == null || signal.mappedEngine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⏳ Сигнал ещё не классифицирован')),
      );
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🚀 Запуск сигнала'),
        content: Text(
          'Запустить ${signal.pair} на Binance?\n'
          'Стратегия: ${signal.mappedStrategy} (${signal.engineLabel})\n'
          'Режим: Виртуальный (реальные данные + виртуальный баланс) 🧪',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Запустить 🚀',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await repository.startSignalRun(signal.id,
          mode: 'virtual');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '🚀 ${signal.pair} запущен на Binance '
                '(${signal.engineLabel}, run #${result['run_id']})'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка запуска: $e')),
        );
      }
    }
  }

  void _showSignalDetail(BuildContext context) {
    final pc = PfColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(PfSpacing.lg),
        decoration: BoxDecoration(
          color: pc.backgroundC,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: pc.mutedC,
                  borderRadius: PfRadius.borderRadiusPill,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('${signal.typeEmoji} ',
                    style: const TextStyle(fontSize: 24)),
                Text(
                  signal.pair,
                  style: PfTypography.titleLg.copyWith(color: pc.foregroundC),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _detailRow('Канал', signal.channel, pc),
            _detailRow('Биржа', signal.exchange, pc),
            if (signal.priceRange != null)
              _detailRow('Диапазон',
                  '${signal.priceRange!.toStringAsFixed(2)}%', pc),
            if (signal.vol60m != null)
              _detailRow('Volume 60m', '\$${_formatVolume(signal.vol60m!)}', pc),
            if (signal.vol10m != null)
              _detailRow('Volume 10m', '\$${_formatVolume(signal.vol10m!)}', pc),
            if (signal.slope != null)
              _detailRow('Наклон', signal.slope!.toStringAsFixed(2), pc),
            if (signal.topRatio != null)
              _detailRow('Top ratio', signal.topRatio!.toStringAsFixed(4), pc),
            if (signal.botRatio != null)
              _detailRow('Bot ratio', signal.botRatio!.toStringAsFixed(4), pc),
            if (signal.mappedStrategy != null)
              _detailRow('Стратегия', signal.mappedStrategy!, pc),
            if (signal.mappedEngine != null)
              _detailRow('Движок', signal.engineLabel, pc),
            if (signal.confidence != null)
              _detailRow(
                  'Уверенность', '${(signal.confidence! * 100).toInt()}%', pc),
            if (signal.mappedExchangeFallback != null)
              _detailRow('Fallback биржа',
                  signal.mappedExchangeFallback!.toUpperCase(), pc),
            if (signal.mappedParams != null &&
                signal.mappedParams!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Рекомендованные параметры:',
                style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC),
              ),
              const SizedBox(height: 4),
              ...signal.mappedParams!.entries.map((e) => _detailRow(
                    e.key,
                    e.value.toString(),
                    pc,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, PfColors pc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: PfTypography.bodySm.copyWith(
                color: pc.mutedForegroundC,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: PfTypography.bodyMd.copyWith(color: pc.foregroundC),
            ),
          ),
        ],
      ),
    );
  }

  String _formatVolume(double vol) {
    if (vol >= 1_000_000) return '${(vol / 1_000_000).toStringAsFixed(1)}M';
    if (vol >= 1_000) return '${(vol / 1_000).toStringAsFixed(1)}K';
    return vol.toStringAsFixed(0);
  }
}

/// Inline metric widget for signal details.
class _SignalMetric extends StatelessWidget {
  final String label;
  final String value;
  final PfColors pc;

  const _SignalMetric({
    required this.label,
    required this.value,
    required this.pc,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PfTypography.caption.copyWith(
            color: pc.mutedForegroundC,
            fontSize: 10,
          ),
        ),
        Text(
          value,
          style: PfTypography.bodySm.copyWith(
            color: pc.foregroundC,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
