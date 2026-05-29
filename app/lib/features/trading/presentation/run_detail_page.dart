import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/theme.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final run = await widget.repository.getRun(widget.runId);
      if (mounted) {
        setState(() {
          _run = run;
          _loading = false;
        });
      }
      _loadTrades();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTrades() async {
    setState(() => _loadingTrades = true);
    try {
      final result = await widget.repository.getRunTrades(widget.runId);
      if (mounted) {
        setState(() {
          _trades = result.items;
          _loadingTrades = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTrades = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const PhosphorIcon(PhosphorIconsFill.caretLeft),
          onPressed: () => context.go('/trading'),
        ),
        title: Text(
          _run?.strategyName ?? 'Детали запуска',
          style: theme.appBarTheme.titleTextStyle,
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _run == null
              ? Center(
                  child: Text(
                    'Запуск не найден',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStatusCard(theme, isDark),
                      const SizedBox(height: 16),
                      _buildInfoCard(theme, isDark),
                      const SizedBox(height: 24),
                      Text(
                        'Сделки',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
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
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        )
                      else
                        ...List.generate(
                          _trades.length,
                          (index) => _buildTradeCard(
                              _trades[index], theme),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, bool isDark) {
    return Card(
      color: isDark ? AppTheme.cardColor : AppTheme.lightCardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _statusIcon(_run!.status, 40),
            const SizedBox(height: 12),
            Text(
              _run!.statusLabel,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _run!.modeLabel,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem(
                  theme,
                  'PNL',
                  '${_run!.pnl != null ? (_run!.pnl! >= 0 ? '+' : '') : ''}\$${_run!.pnl?.toStringAsFixed(2) ?? '0.00'}',
                  _run!.pnl != null && _run!.pnl! >= 0
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFE53935),
                ),
                _statItem(
                  theme,
                  'Баланс',
                  '\$${_run!.finalBalance?.toStringAsFixed(0) ?? _run!.startingBalance?.toStringAsFixed(0) ?? '—'}',
                  null,
                ),
                _statItem(
                  theme,
                  'Сделки',
                  '${_run!.totalTrades ?? 0}',
                  null,
                ),
                if (_run!.successRate != null)
                  _statItem(
                    theme,
                    'Успех',
                    '${_run!.successRate!.toStringAsFixed(1)}%',
                    null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(
      ThemeData theme, String label, String value, Color? valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: valueColor ?? theme.textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildInfoCard(ThemeData theme, bool isDark) {
    final config = _run!.config;
    return Card(
      color: isDark ? AppTheme.cardColor : AppTheme.lightCardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Конфигурация',
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 12),
            ...config.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          entry.key,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${entry.value}',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildTradeCard(TradingTrade trade, ThemeData theme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      color: isDark ? AppTheme.cardColor : AppTheme.lightCardColor,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: side icon + type + PnL ──
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: trade.isBuy
                        ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                        : const Color(0xFFE53935).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: PhosphorIcon(
                      trade.isBuy
                          ? PhosphorIconsFill.arrowFatUp
                          : PhosphorIconsFill.arrowFatDown,
                      size: 16,
                      color: trade.isBuy
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFE53935),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trade.isBuy ? 'Покупка' : 'Продажа',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Цена входа: \$${trade.entryPrice.toStringAsFixed(2)}'
                        '${trade.exitPrice != null ? ' → \$${trade.exitPrice!.toStringAsFixed(2)}' : ''}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: trade.pnl >= 0
                        ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                        : const Color(0xFFE53935).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${trade.pnl >= 0 ? '+' : ''}\$${trade.pnl.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: trade.pnl >= 0
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFE53935),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Row 2: entry time ──
            Row(
              children: [
                PhosphorIcon(
                  PhosphorIconsFill.signIn,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Вход: ${trade.entryDate} ${trade.entryTimeStr}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                PhosphorIcon(
                  PhosphorIconsFill.signOut,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Выход: ${trade.exitDateTimeStr}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(String status, double size) {
    switch (status) {
      case 'running':
      case 'pending':
        return const PhosphorIcon(
          PhosphorIconsFill.play,
          size: 40,
          color: Color(0xFF2196F3),
        );
      case 'done':
        return const PhosphorIcon(
          PhosphorIconsFill.checkCircle,
          size: 40,
          color: Color(0xFF4CAF50),
        );
      case 'stopped':
        return const PhosphorIcon(
          PhosphorIconsFill.stopCircle,
          size: 40,
          color: Color(0xFFFF9800),
        );
      case 'error':
        return const PhosphorIcon(
          PhosphorIconsFill.xCircle,
          size: 40,
          color: Color(0xFFE53935),
        );
      default:
        return const PhosphorIcon(
          PhosphorIconsFill.question,
          size: 40,
          color: Colors.grey,
        );
    }
  }
}

extension _RunModeLabel on TradingRun {
  String get modeLabel {
    switch (mode) {
      case 'history':
        return 'Исторические данные 📜';
      case 'virtual':
        return 'Виртуальный баланс 💻';
      case 'real':
        return 'Реальный баланс 💰';
      default:
        return mode;
    }
  }
}
