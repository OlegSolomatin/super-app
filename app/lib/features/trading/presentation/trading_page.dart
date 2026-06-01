import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/theme.dart';
import 'package:app/features/trading/data/models/trading_run.dart';
import 'package:app/features/trading/data/trading_repository.dart';
import 'package:app/shared/widgets/responsive_layout.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cleanupStaleRuns();
    _loadActiveRuns();
    _loadHistoryRuns();
    // Poll active runs every 2 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollActiveRuns();
    });
  }

  Future<void> _cleanupStaleRuns() async {
    try {
      await widget.repository.cleanupStaleRuns();
    } catch (_) {}
  }

  /// Quick poll — no loading spinner, just update list.
  Future<void> _pollActiveRuns() async {
    try {
      final result = await widget.repository.getRuns(status: 'running');
      if (!mounted) return;
      final hadActive = _activeRuns.isNotEmpty;
      setState(() {
        _activeRuns = result.items;
      });
      // If active runs just finished — reload history
      if (hadActive && result.items.isEmpty) {
        _loadHistoryRuns();
      }
    } catch (_) {
      // Silently retry on next tick
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveRuns() async {
    setState(() => _loadingActive = true);
    try {
      final result = await widget.repository.getRuns(status: 'running');
      if (mounted) {
        setState(() {
          _activeRuns = result.items;
          _loadingActive = false;
        });
      }
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
      if (mounted) {
        setState(() {
          _historyRuns = all;
          _loadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const PhosphorIcon(PhosphorIconsFill.caretLeft),
          onPressed: () => context.go('/'),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              PhosphorIconsFill.chartLine,
              color: theme.appBarTheme.foregroundColor,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Text('Торговля'),
          ],
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: PhosphorIcon(
                PhosphorIconsFill.list,
                color: theme.appBarTheme.foregroundColor,
              ),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _buildDrawer(context),
      body: ConstrainedContent(
        child: Column(
        children: [
          const SizedBox(height: 16),
          // Strategy button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => context.go('/trading/wizard'),
                icon: const PhosphorIcon(
                  PhosphorIconsFill.rocket,
                  size: 22,
                ),
                label: const Text(
                  'Стратегия',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Tab bar
          Container(
            color: isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor,
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.accentColor,
              unselectedLabelColor:
                  isDark ? Colors.white54 : AppTheme.lightTextSecondary,
              indicatorColor: AppTheme.accentColor,
              tabs: const [
                Tab(text: 'Запущенные'),
                Tab(text: 'История'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildActiveTab(),
                _buildHistoryTab(),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      backgroundColor:
          isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: AppTheme.accentColor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const PhosphorIcon(
                  PhosphorIconsFill.chartLine,
                  size: 40,
                  color: Colors.white,
                ),
                const SizedBox(height: 8),
                Text(
                  'Торговля',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                      ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const PhosphorIcon(PhosphorIconsFill.rocket),
            title: const Text('Новая стратегия'),
            onTap: () {
              Navigator.pop(context);
              context.go('/trading/wizard');
            },
          ),
          ListTile(
            leading: const PhosphorIcon(PhosphorIconsFill.clock),
            title: const Text('Активные'),
            onTap: () {
              Navigator.pop(context);
              _tabController.animateTo(0);
            },
          ),
          ListTile(
            leading: const PhosphorIcon(PhosphorIconsFill.clockCounterClockwise),
            title: const Text('История'),
            onTap: () {
              Navigator.pop(context);
              _tabController.animateTo(1);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTab() {
    if (_loadingActive) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_activeRuns.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadActiveRuns,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.3,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(
                      PhosphorIconsFill.rocket,
                      size: 56,
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Нет активных стратегий',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withValues(alpha: 0.5),
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Запустите новую стратегию, нажав\nкнопку "Стратегия"',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withValues(alpha: 0.3),
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadActiveRuns,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _activeRuns.length,
        itemBuilder: (context, index) {
          final run = _activeRuns[index];
          return _buildActiveRunCard(run);
        },
      ),
    );
  }

  Widget _buildActiveRunCard(TradingRun run) {
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? AppTheme.cardColor : AppTheme.lightCardColor,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PhosphorIcon(
                  PhosphorIconsFill.rocket,
                  size: 18,
                  color: AppTheme.accentColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    run.strategyName ?? 'Стратегия',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _modeColor(run.mode).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(
                        _modeIcon(run.mode),
                        size: 14,
                        color: _modeColor(run.mode),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _modeLabel(run.mode),
                        style: TextStyle(
                          fontSize: 11,
                          color: _modeColor(run.mode),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _coinIconSmall(run.coinIconUrl, run.baseCoin, isDark),
                const SizedBox(width: 6),
                Text(
                  run.pairDisplay,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _infoChip(
                  icon: PhosphorIconsFill.wallet,
                  label: '\$${run.startingBalance?.toStringAsFixed(0) ?? '—'}',
                  theme: theme,
                ),
                const SizedBox(width: 12),
                _infoChip(
                  icon: PhosphorIconsFill.arrowsLeftRight,
                  label: '${run.totalTrades ?? 0} сделок',
                  theme: theme,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (run.endsAt != null)
                  _infoChip(
                    icon: PhosphorIconsFill.clock,
                    label: _timeRemaining(run.endsAt!),
                    theme: theme,
                  ),
                if (run.endsAt != null) const Spacer(),
                if (run.pnl != null)
                  Text(
                    '+${run.pnl!.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: run.pnl! >= 0
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFE53935),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Progress bar for virtual live runs ──
            if (run.mode == 'virtual' && run.progressPercent != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: run.progressPercent! / 100.0,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    run.progressPercent! < 50
                        ? AppTheme.accentColor
                        : run.progressPercent! < 90
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF4CAF50),
                  ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _coinIconSmall(run.coinIconUrl, run.baseCoin, isDark),
                    const SizedBox(width: 6),
                    Text(
                      run.pairDisplay,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                children: [
                  Text(
                    '${run.progressPercent!.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (run.timeRemainingLabel != null)
                    Text(
                      'Осталось ${run.timeRemainingLabel}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmStopRun(run),
                icon: const PhosphorIcon(
                  PhosphorIconsFill.stop,
                  size: 16,
                ),
                label: const Text(
                  'Остановить',
                  style: TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE53935),
                  side: const BorderSide(color: Color(0xFFE53935)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required ThemeData theme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhosphorIcon(
          icon,
          size: 14,
          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
        ),
      ],
    );
  }

  Widget _coinIconSmall(String? iconUrl, String baseCoin, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 20,
        height: 20,
        child: iconUrl != null
            ? Image.network(
                iconUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _coinLetterBox(baseCoin, isDark),
                loadingBuilder: (_, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _coinLetterBox(baseCoin, isDark);
                },
              )
            : _coinLetterBox(baseCoin, isDark),
      ),
    );
  }

  Widget _coinLetterBox(String baseCoin, bool isDark) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          baseCoin.isNotEmpty ? baseCoin.substring(0, 1).toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  String _timeRemaining(DateTime endsAt) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Завершён';
    if (remaining.inDays > 0) return '${remaining.inDays}д ${remaining.inHours % 24}ч';
    if (remaining.inHours > 0) return '${remaining.inHours}ч ${remaining.inMinutes % 60}м';
    return '${remaining.inMinutes}м';
  }

  Future<void> _confirmStopRun(TradingRun run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardTheme.color,
        title: const Text('Остановить запуск?'),
        content: Text('Стратегия "${run.strategyName ?? run.id}" будет остановлена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE53935)),
            child: const Text('Остановить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.repository.deleteRun(run.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запуск остановлен'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        _loadActiveRuns();
        _loadHistoryRuns();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
    }
  }

  Widget _buildHistoryTab() {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_historyRuns.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadHistoryRuns,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.3,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(
                      PhosphorIconsFill.clockCounterClockwise,
                      size: 56,
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'История пуста',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withValues(alpha: 0.5),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistoryRuns,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _historyRuns.length,
        itemBuilder: (context, index) {
          final run = _historyRuns[index];
          return _buildHistoryRunCard(run);
        },
      ),
    );
  }

  Widget _buildHistoryRunCard(TradingRun run) {
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? AppTheme.cardColor : AppTheme.lightCardColor,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/trading/runs/${run.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _statusIcon(run.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      run.strategyName ?? 'Стратегия',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 16,
                      ),
                    ),
                  ),
                if (run.pnl != null)
                  Text(
                    '${run.pnl! >= 0 ? '+' : ''}${run.pnl!.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: run.pnl! >= 0
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFE53935),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  _coinIconSmall(run.coinIconUrl, run.baseCoin, isDark),
                  const SizedBox(width: 6),
                  Text(
                    run.pairDisplay,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (run.finalBalance != null)
                    _infoChip(
                      icon: PhosphorIconsFill.wallet,
                      label:
                          '\$${run.finalBalance!.toStringAsFixed(0)}',
                      theme: theme,
                    ),
                  if (run.finalBalance != null) const SizedBox(width: 12),
                  if (run.totalTrades != null)
                    _infoChip(
                      icon: PhosphorIconsFill.arrowsLeftRight,
                      label: '${run.totalTrades} сделок',
                      theme: theme,
                    ),
                  if (run.totalTrades != null) const SizedBox(width: 12),
                  if (run.successRate != null)
                    _infoChip(
                      icon: PhosphorIconsFill.checkCircle,
                      label:
                          '${run.successRate!.toStringAsFixed(1)}%',
                      theme: theme,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'done':
        return const PhosphorIcon(
          PhosphorIconsFill.checkCircle,
          size: 20,
          color: Color(0xFF4CAF50),
        );
      case 'stopped':
        return const PhosphorIcon(
          PhosphorIconsFill.stopCircle,
          size: 20,
          color: Color(0xFFFF9800),
        );
      case 'error':
        return const PhosphorIcon(
          PhosphorIconsFill.xCircle,
          size: 20,
          color: Color(0xFFE53935),
        );
      default:
        return const PhosphorIcon(
          PhosphorIconsFill.question,
          size: 20,
          color: Colors.grey,
        );
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'history':
        return const Color(0xFF4CAF50);
      case 'virtual':
        return const Color(0xFF2196F3);
      case 'real':
        return const Color(0xFFE53935);
      default:
        return Colors.grey;
    }
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'history':
        return PhosphorIconsFill.scroll;
      case 'virtual':
        return PhosphorIconsFill.desktop;
      case 'real':
        return PhosphorIconsFill.coins;
      default:
        return PhosphorIconsFill.question;
    }
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'history':
        return 'История';
      case 'virtual':
        return 'Виртуал';
      case 'real':
        return 'Реал';
      default:
        return mode;
    }
  }
}
