import 'dart:async';
import 'dart:convert';
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
import 'package:app/shared/widgets/pf_divider.dart';
import 'package:app/features/trading/data/trading_repository.dart';
import 'package:app/features/trading/data/strategy_names.dart';

class OrderBookRunDetailPage extends StatefulWidget {
  final int runId;
  final TradingRepository repository;

  const OrderBookRunDetailPage({
    super.key,
    required this.runId,
    required this.repository,
  });

  @override
  State<OrderBookRunDetailPage> createState() => _OrderBookRunDetailPageState();
}

class _OrderBookRunDetailPageState extends State<OrderBookRunDetailPage> {
  Map<String, dynamic>? _run;
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ThemeProvider>().setSection(SectionTheme.trading);
      }
    });
    _loadData();
    // Poll every 5s for active runs
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_run != null && _run!['status'] == 'running') {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final data = await widget.repository.getOrderBookRun(widget.runId);
      if (mounted) setState(() { _run = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
    final strategyId = _run?['strategy'] as String?;
    final pair = _run?['pair'] as String? ?? 'OB';
    final name = translateStrategy(strategyId);

    return AdaptiveScaffold(
      title: '$name · $pair',
      showBackButton: true,
      currentPath: '/trading/ob-run/${widget.runId}',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _run == null
              ? Center(
                  child: Text(
                    'Запуск не найден',
                    style: PfTypography.bodyLg.copyWith(color: pc.mutedForegroundC),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(PfSpacing.md),
                    children: [
                      _buildHeader(pc),
                      const SizedBox(height: PfSpacing.md),
                      _buildBalanceCard(pc),
                      const SizedBox(height: PfSpacing.md),
                      _buildConfigCard(pc),
                      if (_run!['open_trade_json'] != null) ...[
                        const SizedBox(height: PfSpacing.md),
                        _buildCurrentTradeCard(pc, _run!['open_trade_json'] as String),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(PfColors pc) {
    final status = _run!['status'] as String? ?? 'unknown';
    final isActive = status == 'running';
    final strategyId = _run!['strategy'] as String?;
    final pair = _run!['pair'] as String? ?? '—';

    final statusBadge = isActive
        ? const PfBadge(variant: 'success', label: 'Активна')
        : status == 'error'
            ? const PfBadge(variant: 'destructive', label: 'Ошибка')
            : status == 'done'
                ? const PfBadge(variant: 'info', label: 'Завершена')
                : const PfBadge(variant: 'default', label: 'Остановлена');

    final startedAt = _run!['started_at'] != null
        ? DateTime.parse(_run!['started_at'] as String)
        : null;

    return PfCard(
      padding: const EdgeInsets.all(PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  translateStrategy(strategyId),
                  style: PfTypography.titleLg.copyWith(color: pc.foregroundC),
                ),
              ),
              statusBadge,
            ],
          ),
          const SizedBox(height: PfSpacing.sm),
          Row(
            children: [
              Expanded(child: _StatCell(label: 'Пара', value: pair, mono: true)),
              Expanded(child: _StatCell(label: 'Сделок', value: '${_run!['total_trades'] ?? 0}')),
            ],
          ),
          if (startedAt != null) ...[
            const SizedBox(height: PfSpacing.xs),
            Text(
              _formatDate(startedAt),
              style: PfTypography.caption.copyWith(color: pc.mutedForegroundC),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBalanceCard(PfColors pc) {
    final startBalance = (_run!['initial_balance'] as num?)?.toDouble();
    final currentBalance = (_run!['current_balance'] as num?)?.toDouble();
    final status = _run!['status'] as String? ?? 'unknown';
    final isActive = status == 'running';
    final totalTrades = (_run!['total_trades'] as num?)?.toInt() ?? 0;
    final totalPnl = (_run!['total_pnl'] as num?)?.toDouble() ?? 0.0;
    final displayBalance = currentBalance ?? startBalance;

    return PfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Баланс',
            style: PfTypography.titleMd.copyWith(
              fontSize: 14,
              color: pc.foregroundC,
            ),
          ),
          const SizedBox(height: PfSpacing.sm),
          const PfDivider(),
          const SizedBox(height: PfSpacing.sm),
          _InfoRow(label: 'Стартовый', value: '\$${_fmtBalance(startBalance)}'),
          const SizedBox(height: 2),
          _InfoRow(
            label: isActive ? 'Текущий' : 'Итоговый',
            value: '\$${_fmtBalance(displayBalance)}',
            valueColor: displayBalance != null && startBalance != null
                ? (displayBalance >= startBalance
                    ? PfColors.success
                    : PfColors.destructive)
                : null,
          ),
          const SizedBox(height: PfSpacing.sm),
          const PfDivider(),
          const SizedBox(height: PfSpacing.sm),
          _InfoRow(label: 'Сделок', value: '$totalTrades'),
          _InfoRow(
            label: 'Общий PnL',
            value: totalPnl != 0 ? '\$${totalPnl.toStringAsFixed(2)}' : '—',
            valueColor: totalPnl >= 0 ? PfColors.success : PfColors.destructive,
          ),
        ],
      ),
    );
  }

  Widget _buildConfigCard(PfColors pc) {
    final config = _run!['config'] as Map<String, dynamic>? ?? {};

    return PfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Настройки',
            style: PfTypography.titleMd.copyWith(
              fontSize: 14,
              color: pc.foregroundC,
            ),
          ),
          const SizedBox(height: PfSpacing.sm),
          const PfDivider(),
          const SizedBox(height: PfSpacing.sm),
          ...config.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        translateConfigKey(e.key),
                        style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        formatConfigValue(e.value),
                        style: PfTypography.bodySm.copyWith(
                          color: pc.foregroundC,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildCurrentTradeCard(PfColors pc, String tradeJson) {
    try {
      final trade = jsonDecode(tradeJson) as Map<String, dynamic>;
      final side = trade['side'] as String? ?? 'BUY';
      final isBuy = side.toUpperCase() == 'BUY';
      final entryPrice = (trade['entry_price'] as num?)?.toDouble();
      final quantity = (trade['quantity'] as num?)?.toDouble();
      final pnl = (trade['pnl'] as num?)?.toDouble();
      final pnlPct = (trade['pnl_pct'] as num?)?.toDouble();
      final pair = trade['pair'] as String? ?? '—';
      final ageSec = (trade['age_seconds'] as num?)?.toInt() ?? 0;
      final ageStr = ageSec > 60 ? '${ageSec ~/ 60}м ${ageSec % 60}с' : '${ageSec}с';

      return PfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PhosphorIcon(
                  isBuy ? PhosphorIconsFill.trendUp : PhosphorIconsFill.trendDown,
                  size: 16,
                  color: isBuy ? PfColors.success : PfColors.destructive,
                ),
                const SizedBox(width: 8),
                Text(
                  'Текущая сделка',
                  style: PfTypography.titleMd.copyWith(
                    fontSize: 14,
                    color: pc.foregroundC,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PfSpacing.sm),
            const PfDivider(),
            const SizedBox(height: PfSpacing.sm),
            _InfoRow(label: 'Пара', value: pair),
            _InfoRow(
              label: 'Сторона',
              value: isBuy ? '🟢 Покупка' : '🔴 Продажа',
            ),
            if (entryPrice != null)
              _InfoRow(label: 'Цена входа', value: '\$${entryPrice.toStringAsFixed(4)}'),
            if (quantity != null)
              _InfoRow(label: 'Объём', value: quantity.toStringAsFixed(6)),
            if (pnl != null)
              _InfoRow(
                label: 'Текущий PnL',
                value: '\$${pnl.toStringAsFixed(2)}${pnlPct != null ? ' (${pnlPct.toStringAsFixed(2)}%)' : ''}',
                valueColor: pnl >= 0 ? PfColors.success : PfColors.destructive,
              ),
            _InfoRow(label: 'В позиции', value: ageStr),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  String _fmtBalance(double? v) => v != null ? v.toStringAsFixed(2) : '—';

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ─── Stat Cell (для header) ────────────────────────────────────────────
class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _StatCell({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: (mono ? PfTypography.number : PfTypography.titleMd).copyWith(
            color: pc.foregroundC,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: PfTypography.caption.copyWith(color: pc.mutedForegroundC),
        ),
      ],
    );
  }
}

// ─── Info Row (для настроек/баланса) ──────────────────────────────────
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: PfTypography.bodySm.copyWith(
                color: valueColor ?? pc.foregroundC,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
