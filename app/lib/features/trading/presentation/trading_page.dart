import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:app/core/theme_provider.dart';
import 'package:app/core/section_theme.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/adaptive_scaffold.dart';
import 'package:app/shared/widgets/pf_card.dart';
import 'package:app/shared/widgets/pf_badge.dart';
import 'package:app/shared/widgets/pf_button.dart';
import 'package:app/shared/widgets/pf_divider.dart';
import 'package:app/features/trading/data/models/trading_run.dart';
import 'package:app/features/trading/data/trading_repository.dart';

class TradingPage extends StatefulWidget {
  final TradingRepository repository;

  const TradingPage({super.key, required this.repository});

  @override
  State<TradingPage> createState() => _TradingPageState();
}

class _TradingPageState extends State<TradingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<TradingRun> _activeRuns = [];
  List<TradingRun> _historyRuns = [];
  bool _loadingActive = true;
  bool _loadingHistory = true;
  Timer? _pollTimer;
  /// Scan progress cache: run_id -> {status, scanned_pairs, total_pairs, ...}
  final Map<String, Map<String, dynamic>> _scanProgress = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ThemeProvider>().setSection(SectionTheme.trading);
      }
    });
    _cleanupStaleRuns();
    _loadActiveRuns();
    _loadHistoryRuns();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollActiveRuns();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cleanupStaleRuns() async {
    try {
      await widget.repository.cleanupStaleRuns();
    } catch (_) {}
  }

  Future<void> _pollActiveRuns() async {
    try {
      final result = await widget.repository.getRuns(status: 'running');
      if (!mounted) return;
      final hadActive = _activeRuns.isNotEmpty;
      setState(() => _activeRuns = result.items);
      if (hadActive && result.items.isEmpty) {
        _loadHistoryRuns();
      }
      // Poll scan progress for scanner runs (molot)
      for (final run in result.items) {
        if (run.isScanner) {
          final progress = await widget.repository.getRunScanProgress(run.id);
          if (mounted) {
            setState(() => _scanProgress[run.id] = progress);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadActiveRuns() async {
    setState(() => _loadingActive = true);
    try {
      final result = await widget.repository.getRuns(status: 'running');
      if (mounted) setState(() { _activeRuns = result.items; _loadingActive = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingActive = false);
    }
  }

  Future<void> _loadHistoryRuns() async {
    setState(() => _loadingHistory = true);
    try {
      final done = await widget.repository.getRuns(status: 'done');
      final stopped = await widget.repository.getRuns(status: 'stopped');
      final error = await widget.repository.getRuns(status: 'error');
      final all = [...done.items, ...stopped.items, ...error.items];
      all.sort((a, b) {
        final aDate = a.createdAt ?? DateTime(2000);
        final bDate = b.createdAt ?? DateTime(2000);
        return bDate.compareTo(aDate);
      });
      if (mounted) setState(() { _historyRuns = all; _loadingHistory = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Трейдинг',
      currentPath: '/trading',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header + New Strategy button ──────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(PfSpacing.lg, PfSpacing.lg, PfSpacing.lg, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Торговые стратегии',
                    style: PfTypography.displayMd.copyWith(color: PfColors.foreground),
                  ),
                ),
                PfButton(
                  variant: 'primary',
                  size: 'md',
                  label: 'Стратегия',
                  icon: PhosphorIconsFill.rocket,
                  onPressed: () => context.go('/trading/wizard'),
                ),
              ],
            ),
          ),
          const SizedBox(height: PfSpacing.lg),

          // ── Pill Tabs ─────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: PfColors.surface,
              borderRadius: PfRadius.borderRadiusPill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PillTab(
                  label: 'Запущенные',
                  count: _activeRuns.length,
                  isActive: _tabController.index == 0,
                  onTap: () => _tabController.animateTo(0),
                ),
                const SizedBox(width: 2),
                _PillTab(
                  label: 'История',
                  count: _historyRuns.length,
                  isActive: _tabController.index == 1,
                  onTap: () => _tabController.animateTo(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: PfSpacing.md),

          // ── Tab Content ───────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRunsList(
                  runs: _activeRuns,
                  loading: _loadingActive,
                  emptyIcon: PhosphorIconsFill.rocket,
                  emptyText: 'Нет активных стратегий',
                  emptySubtext: 'Запустите новую стратегию, чтобы увидеть результаты',
                  repository: widget.repository,
                ),
                _buildRunsList(
                  runs: _historyRuns,
                  loading: _loadingHistory,
                  emptyIcon: PhosphorIconsFill.clockCounterClockwise,
                  emptyText: 'История пуста',
                  emptySubtext: 'Завершённые стратегии появятся здесь',
                  repository: widget.repository,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunsList({
    required List<TradingRun> runs,
    required bool loading,
    required PhosphorIconData emptyIcon,
    required String emptyText,
    required String emptySubtext,
    required TradingRepository repository,
  }) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (runs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              emptyIcon,
              size: 48,
              color: PfColors.mutedForeground.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              emptyText,
              style: PfTypography.titleMd.copyWith(color: PfColors.mutedForeground),
            ),
            const SizedBox(height: 4),
            Text(
              emptySubtext,
              style: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _tabController.index == 0
          ? _loadActiveRuns()
          : _loadHistoryRuns(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
        itemCount: runs.length,
        separatorBuilder: (_, __) => const SizedBox(height: PfSpacing.sm),
        itemBuilder: (context, index) {
          final run = runs[index];
          return _TradingRunCard(
            run: run,
            scanProgress: _scanProgress[run.id],
            onTap: () => context.go('/trading/run/${run.id}'),
          );
        },
      ),
    );
  }
}

// ─── Pill Tab ──────────────────────────────────────────────────────────
class _PillTab extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _PillTab({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: PfRadius.borderRadiusPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: PfTypography.button.copyWith(
                color: isActive
                    ? const Color(0xFF181A20)
                    : PfColors.mutedForeground,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF181A20).withValues(alpha: 0.15)
                    : PfColors.muted,
                borderRadius: PfRadius.borderRadiusPill,
              ),
              child: Text(
                '$count',
                style: PfTypography.caption.copyWith(
                  color: isActive
                      ? const Color(0xFF181A20)
                      : PfColors.mutedForeground,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Trading Run Card ─────────────────────────────────────────────────
class _TradingRunCard extends StatelessWidget {
  final TradingRun run;
  final Map<String, dynamic>? scanProgress;
  final VoidCallback onTap;

  const _TradingRunCard({
    required this.run,
    this.scanProgress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = run.status == 'running' || run.status == 'pending';
    final isError = run.status == 'error';
    final isDone = run.status == 'done';
    final pnl = run.pnl;

    final statusBadge = isActive
        ? const PfBadge(variant: 'success', label: 'Активна')
        : isError
            ? const PfBadge(variant: 'destructive', label: 'Ошибка')
            : isDone
                ? const PfBadge(variant: 'info', label: 'Завершена')
                : const PfBadge(variant: 'default', label: 'Остановлена');

    return PfCard(
      variant: 'trading',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row: strategy name + status
          Row(
            children: [
              Expanded(
                child: Text(
                  run.strategyName ?? run.config['strategy'] ?? 'Стратегия',
                  style: PfTypography.titleMd.copyWith(color: PfColors.foreground),
                ),
              ),
              statusBadge,
            ],
          ),
          const SizedBox(height: PfSpacing.sm),
          const PfDivider(),
          const SizedBox(height: PfSpacing.sm),
          // Info row
          Row(
            children: [
              _InfoCell(
                label: 'Пара',
                value: run.config['pair'] ?? '—',
                mono: true,
              ),
              const SizedBox(width: PfSpacing.lg),
              _InfoCell(
                label: 'Таймфрейм',
                value: run.config['timeframe'] ?? '—',
              ),
              const Spacer(),
              // PnL
              if (pnl != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'PnL',
                      style: PfTypography.caption.copyWith(color: PfColors.mutedForeground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '\$${pnl.toStringAsFixed(2)}',
                      style: PfTypography.number.copyWith(
                        color: pnl >= 0 ? PfColors.success : PfColors.destructive,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // ── Progress bar for active runs ───────────────
          if (isActive) ...[
            if (run.isScanner && scanProgress != null && scanProgress!['status'] == 'scanning')
              _buildScanProgress(scanProgress!)
            else if (run.isVirtual && run.progressPercent != null)
              _buildTimeProgress(run)
            else if (!run.isScanner && !run.isVirtual)
              _buildEstimatedTime(run),
          ],
        ],
      ),
    );
  }

  /// Scan progress — for all_pairs_hammer / all_pairs_inverse_hammer
  Widget _buildScanProgress(Map<String, dynamic> progress) {
    final total = (progress['total_pairs'] as num?)?.toInt() ?? 0;
    final scanned = (progress['scanned_pairs'] as num?)?.toInt() ?? 0;
    final currentPair = (progress['current_pair'] as String?) ?? '';
    final eta = (progress['estimated_remaining_seconds'] as num?)?.toDouble() ?? 0;
    final pct = total > 0 ? scanned / total : 0.0;

    String etaLabel = '';
    if (eta > 0) {
      if (eta > 60) {
        etaLabel = '${(eta / 60).round()} мин';
      } else {
        etaLabel = '${eta.round()} сек';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current pair + progress text
          Row(
            children: [
              Expanded(
                child: Text(
                  currentPair.isNotEmpty ? currentPair : 'Сканирование…',
                  style: PfTypography.caption.copyWith(
                    color: PfColors.accentTrading,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$scanned / $total',
                style: PfTypography.caption.copyWith(
                  color: PfColors.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar
          ClipRRect(
            borderRadius: PfRadius.borderRadiusPill,
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              backgroundColor: PfColors.surface,
              valueColor: AlwaysStoppedAnimation(PfColors.accentTrading),
              minHeight: 6,
            ),
          ),
          if (etaLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Осталось: $etaLabel',
              style: PfTypography.caption.copyWith(
                color: PfColors.mutedForeground.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Time-based progress — for virtual/real mode with duration
  Widget _buildTimeProgress(TradingRun run) {
    final progress = (run.progressPercent ?? 0.0) / 100.0;
    final remaining = run.timeRemainingLabel;

    return Padding(
      padding: const EdgeInsets.only(top: PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (remaining != null)
                Text(
                  remaining,
                  style: PfTypography.caption.copyWith(
                    color: PfColors.accentTrading,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const Spacer(),
              Text(
                '${(progress * 100).toStringAsFixed(1)}%',
                style: PfTypography.caption.copyWith(
                  color: PfColors.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: PfRadius.borderRadiusPill,
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: PfColors.surface,
              valueColor: AlwaysStoppedAnimation(PfColors.accentTrading),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  /// Estimated time text — for fast history mode runs
  Widget _buildEstimatedTime(TradingRun run) {
    final label = run.estimatedTimeLabel ?? '~7 сек';
    return Padding(
      padding: const EdgeInsets.only(top: PfSpacing.sm),
      child: Row(
        children: [
          PhosphorIcon(
            PhosphorIconsFill.clock,
            size: 14,
            color: PfColors.mutedForeground.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Text(
            'Примерное время расчёта: $label',
            style: PfTypography.caption.copyWith(
              color: PfColors.mutedForeground.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info Cell ────────────────────────────────────────────────────────
class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _InfoCell({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PfTypography.caption.copyWith(color: PfColors.mutedForeground),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: mono
              ? PfTypography.number.copyWith(color: PfColors.foreground)
              : PfTypography.bodyMd.copyWith(color: PfColors.foreground),
        ),
      ],
    );
  }
}
