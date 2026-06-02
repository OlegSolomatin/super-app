import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
import 'package:app/shared/widgets/pf_divider.dart';
import 'package:app/features/trading/data/models/trading_run.dart';
import 'package:app/features/trading/data/models/trading_trade.dart';
import 'package:app/features/trading/data/trading_repository.dart';

class TradingRunDetailPage extends StatefulWidget {
  final String runId;
  final TradingRepository repository;

  const TradingRunDetailPage({
    super.key,
    required this.runId,
    required this.repository,
  });

  @override
  State<TradingRunDetailPage> createState() => _TradingRunDetailPageState();
}

class _TradingRunDetailPageState extends State<TradingRunDetailPage> {
  TradingRun? _run;
  List<TradingTrade> _trades = [];
  bool _loading = true;
  bool _loadingTrades = true;
  Map<String, dynamic>? _scanProgress;
  bool _isScanner = false;

  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ThemeProvider>().setSection(SectionTheme.trading);
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final run = await widget.repository.getRun(widget.runId);
      if (mounted) {
        setState(() {
          _run = run;
          _loading = false;
          _isScanner = (run.config['strategy'] as String? ?? '')
              .contains('all_pairs');
        });
        if (_isScanner && (run.status == 'running' || run.status == 'pending')) {
          _startScanPolling();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    _loadTrades();
  }

  Future<void> _loadTrades() async {
    setState(() => _loadingTrades = true);
    try {
      final trades = await widget.repository.getTrades(widget.runId);
      if (mounted) setState(() { _trades = trades; _loadingTrades = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingTrades = false);
    }
  }

  void _startScanPolling() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      try {
        final progress = await widget.repository.getScanProgress(widget.runId);
        if (mounted) setState(() => _scanProgress = progress);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _run?.strategyName ?? 'Детали запуска';

    return AdaptiveScaffold(
      title: name,
      currentPath: '/trading/run/${widget.runId}',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _run == null
              ? Center(
                  child: Text(
                    'Запуск не найден',
                    style: PfTypography.bodyLg.copyWith(color: PfColors.mutedForeground),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(PfSpacing.md),
                    children: [
                      _buildStatsRow(),
                      const SizedBox(height: PfSpacing.md),
                      _buildInfoCard(),
                      if (_isScanner && _scanProgress != null) ...[
                        const SizedBox(height: PfSpacing.sm),
                        _buildScanProgressCard(),
                      ],
                      const SizedBox(height: PfSpacing.lg),
                      Text(
                        'Сделки',
                        style: PfTypography.titleLg.copyWith(color: PfColors.foreground),
                      ),
                      const SizedBox(height: PfSpacing.sm),
                      if (_loadingTrades)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_trades.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Сделок пока нет',
                              style: PfTypography.bodyMd.copyWith(color: PfColors.mutedForeground),
                            ),
                          ),
                        )
                      else
                        ...List.generate(
                          _trades.length,
                          (index) => Padding(
                            padding: EdgeInsets.only(
                              bottom: index < _trades.length - 1 ? PfSpacing.sm : 0,
                            ),
                            child: _TradeCard(trade: _trades[index]),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  // ─── Stats Row (stat-callout style) ──────────────────────────────
  Widget _buildStatsRow() {
    final run = _run!;

    final isActive = run.status == 'running' || run.status == 'pending';
    final statusBadge = isActive
        ? const PfBadge(variant: 'success', label: 'Активна')
        : run.status == 'error'
            ? const PfBadge(variant: 'destructive', label: 'Ошибка')
            : run.status == 'done'
                ? const PfBadge(variant: 'info', label: 'Завершена')
                : const PfBadge(variant: 'default', label: 'Остановлена');

    return PfCard(
      padding: const EdgeInsets.all(PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with name + status
          Row(
            children: [
              Expanded(
                child: Text(
                  run.strategyName ?? run.config['strategy'] ?? 'Стратегия',
                  style: PfTypography.titleLg.copyWith(color: PfColors.foreground),
                ),
              ),
              statusBadge,
            ],
          ),
          const SizedBox(height: PfSpacing.md),
          // 4 stats
          Row(
            children: [
              Expanded(child: _StatCell(label: 'Пара', value: run.config['pair'] ?? '—', mono: true)),
              Expanded(child: _StatCell(label: 'TF', value: run.config['timeframe'] ?? '—')),
              Expanded(child: _StatCell(
                label: 'PnL',
                value: run.pnl != null ? '\$${run.pnl!.toStringAsFixed(2)}' : '—',
                color: run.pnl != null
                    ? (run.pnl! >= 0 ? PfColors.success : PfColors.destructive)
                    : null,
              )),
              Expanded(child: _StatCell(label: 'Сделок', value: '${_trades.length}')),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Info Card ──────────────────────────────────────────────────
  Widget _buildInfoCard() {
    final run = _run!;
    return PfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Параметры запуска',
            style: PfTypography.titleMd.copyWith(color: PfColors.foreground),
          ),
          const SizedBox(height: PfSpacing.sm),
          const PfDivider(),
          const SizedBox(height: PfSpacing.sm),
          _InfoRow(label: 'Стратегия', value: run.config['strategy'] ?? '—'),
          _InfoRow(label: 'Пара', value: run.config['pair'] ?? '—'),
          _InfoRow(label: 'Таймфрейм', value: run.config['timeframe'] ?? '—'),
          _InfoRow(label: 'Плечо', value: 'x${run.config['leverage'] ?? '1'}'),
          _InfoRow(label: 'Баланс', value: '\$${(run.config['balance'] ?? 1000).toString()}'),
          _InfoRow(label: 'Дата запуска', value: _formatDate(run.createdAt)),
        ],
      ),
    );
  }

  // ─── Scan Progress ──────────────────────────────────────────────
  Widget _buildScanProgressCard() {
    final progress = _scanProgress;
    if (progress == null) return const SizedBox.shrink();

    final scanned = progress['scanned'] ?? 0;
    final total = progress['total'] ?? 1;
    final pnl = progress['pnl'];
    final currentPair = progress['current_pair'] ?? '';
    final ratio = total > 0 ? (scanned as num) / (total as num) : 0.0;

    return PfCard(
      padding: const EdgeInsets.all(PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhosphorIcon(PhosphorIconsFill.magnifyingGlass, size: 16, color: PfColors.success),
              const SizedBox(width: 8),
              Text(
                'Сканирование пар',
                style: PfTypography.titleMd.copyWith(color: PfColors.foreground),
              ),
            ],
          ),
          const SizedBox(height: PfSpacing.sm),
          // Progress bar
          ClipRRect(
            borderRadius: PfRadius.borderRadiusPill,
            child: LinearProgressIndicator(
              value: ratio.toDouble(),
              minHeight: 4,
              backgroundColor: PfColors.muted,
              valueColor: AlwaysStoppedAnimation<Color>(PfColors.success),
            ),
          ),
          const SizedBox(height: PfSpacing.sm),
          Row(
            children: [
              _ScanInfo(label: 'Сканировано', value: '$scanned / $total'),
              if (currentPair.isNotEmpty) ...[
                const SizedBox(width: PfSpacing.md),
                _ScanInfo(label: 'Текущая', value: currentPair),
              ],
              if (pnl != null) ...[
                const Spacer(),
                _ScanInfo(
                  label: 'PnL',
                  value: '\$${(pnl as num).toStringAsFixed(2)}',
                  color: (pnl as num) >= 0 ? PfColors.success : PfColors.destructive,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ─── Stat Cell ────────────────────────────────────────────────────────
class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final Color? color;

  const _StatCell({
    required this.label,
    required this.value,
    this.mono = false,
    this.color,
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
        const SizedBox(height: 4),
        Text(
          value,
          style: mono
              ? PfTypography.number.copyWith(color: color ?? PfColors.foreground)
              : PfTypography.bodyMd.copyWith(color: color ?? PfColors.foreground),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── Info Row ────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: PfTypography.bodyMd.copyWith(color: PfColors.foreground),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Scan Info ───────────────────────────────────────────────────────
class _ScanInfo extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _ScanInfo({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PfTypography.caption.copyWith(color: PfColors.mutedForeground, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: PfTypography.bodySm.copyWith(color: color ?? PfColors.foreground)),
      ],
    );
  }
}

// ─── Trade Card ──────────────────────────────────────────────────────
class _TradeCard extends StatelessWidget {
  final TradingTrade trade;

  const _TradeCard({required this.trade});

  @override
  Widget build(BuildContext context) {
    final pnl = trade.pnl;
    final pnlPositive = pnl != null && pnl >= 0;
    final pnlColor = pnl != null
        ? (pnlPositive ? PfColors.success : PfColors.destructive)
        : null;

    return PfCard(
      variant: 'trading',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: pair + type + PnL
          Row(
            children: [
              if (trade.pair != null && trade.pair!.isNotEmpty)
                PfBadge(
                  variant: 'info',
                  label: trade.pair!,
                ),
              const SizedBox(width: 8),
              PfBadge(
                variant: trade.type == 'long' || trade.type == 'buy' ? 'success' : 'destructive',
                label: (trade.type ?? '—').toUpperCase(),
              ),
              const Spacer(),
              if (pnl != null)
                Text(
                  '\$${pnl.toStringAsFixed(2)}',
                  style: PfTypography.number.copyWith(
                    color: pnlColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: PfSpacing.sm),
          const PfDivider(),
          const SizedBox(height: PfSpacing.sm),
          // Details
          Row(
            children: [
              Expanded(
                child: _StatCell(
                  label: 'Entry',
                  value: trade.entryPrice != null ? '\$${trade.entryPrice!.toStringAsFixed(4)}' : '—',
                  mono: true,
                  color: trade.entryPrice != null ? PfColors.foreground : PfColors.mutedForeground,
                ),
              ),
              Expanded(
                child: _StatCell(
                  label: 'Exit',
                  value: trade.exitPrice != null ? '\$${trade.exitPrice!.toStringAsFixed(4)}' : '—',
                  mono: true,
                  color: trade.exitPrice != null ? PfColors.foreground : PfColors.mutedForeground,
                ),
              ),
              Expanded(
                child: _StatCell(
                  label: 'Кол-во',
                  value: trade.amount != null ? trade.amount!.toStringAsFixed(6) : '—',
                  mono: true,
                ),
              ),
            ],
          ),
          if (trade.exitReason != null && trade.exitReason!.isNotEmpty) ...[
            const SizedBox(height: PfSpacing.xs),
            Text(
              trade.exitReason!,
              style: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}
