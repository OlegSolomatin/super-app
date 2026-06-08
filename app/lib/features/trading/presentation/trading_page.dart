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
import 'package:app/shared/widgets/pf_skeleton.dart';
import 'package:app/features/trading/data/models/trading_run.dart';
import 'package:app/features/trading/data/trading_repository.dart';
import 'package:app/features/trading/data/strategy_names.dart';

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
  int _historyTotal = 0; // реальное общее количество завершённых свечных запусков
  bool _loadingActive = true;
  bool _loadingHistory = true;
  Timer? _pollTimer;

  // OrderBook runs
  List<Map<String, dynamic>> _activeObRuns = []; // только running OB
  List<Map<String, dynamic>> _obRuns = [];        // завершённые OB (история)
  bool _loadingObRuns = false;
  /// Scan progress cache: run_id -> {status, scanned_pairs, total_pairs, ...}
  final Map<String, Map<String, dynamic>> _scanProgress = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    _loadOrderBookRuns();
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
      final obResult = await widget.repository.getOrderBookRuns(status: 'running');
      if (!mounted) return;
      final hadActive = _activeRuns.isNotEmpty || _activeObRuns.isNotEmpty;
      setState(() {
        _activeRuns = result.items;
        _activeObRuns = obResult.items;
      });
      if (hadActive && result.items.isEmpty && obResult.items.isEmpty) {
        _loadHistoryRuns();
        _loadOrderBookRuns();
      } else if (hadActive && result.items.isEmpty) {
        _loadHistoryRuns();
      } else if (hadActive && obResult.items.isEmpty) {
        _loadOrderBookRuns();
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
      // Also fetch running OB runs
      final obResult = await widget.repository.getOrderBookRuns(status: 'running');
      if (mounted) setState(() {
        _activeRuns = result.items;
        _activeObRuns = obResult.items;
        _loadingActive = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingActive = false);
    }
  }

  Future<void> _loadHistoryRuns() async {
    setState(() => _loadingHistory = true);
    try {
      // Fetch all pages or use large pageSize to get all history
      final done = await widget.repository.getRuns(status: 'done', pageSize: 500);
      final stopped = await widget.repository.getRuns(status: 'stopped', pageSize: 500);
      final error = await widget.repository.getRuns(status: 'error', pageSize: 500);
      final all = [...done.items, ...stopped.items, ...error.items];
      all.sort((a, b) {
        final aDate = a.createdAt ?? DateTime(2000);
        final bDate = b.createdAt ?? DateTime(2000);
        return bDate.compareTo(aDate);
      });
      if (mounted) setState(() {
        _historyRuns = all;
        _historyTotal = done.total + stopped.total + error.total;
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadOrderBookRuns() async {
    setState(() => _loadingObRuns = true);
    try {
      // History tab: only completed OB runs (done, stopped, error)
      final done = await widget.repository.getOrderBookRuns(status: 'done', pageSize: 100);
      final stopped = await widget.repository.getOrderBookRuns(status: 'stopped', pageSize: 100);
      final error = await widget.repository.getOrderBookRuns(status: 'error', pageSize: 100);
      final all = [...done.items, ...stopped.items, ...error.items];
      all.sort((a, b) {
        final aDate = (a['started_at'] as String? ?? '');
        final bDate = (b['started_at'] as String? ?? '');
        return bDate.compareTo(aDate);
      });
      if (mounted) {
        setState(() { _obRuns = all; _loadingObRuns = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingObRuns = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
    return AdaptiveScaffold(
      title: 'Трейдинг',
      currentPath: '/trading',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(PfSpacing.lg, PfSpacing.lg, PfSpacing.lg, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Торговые стратегии',
                    style: PfTypography.displayMd.copyWith(color: pc.foregroundC),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PfSpacing.lg),

          // ── Mode Selector ──────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: _ModeCard(
                    icon: PhosphorIconsFill.chartBar,
                    title: 'Стратегии\nпо свечам',
                    subtitle: 'RSI, MACD, ADX,\nсвечные паттерны',
                    badge: '17 стратегий',
                    badgeColor: Color(0xFFFCD535),
                    onTap: () => context.go('/trading/wizard'),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _ModeCard(
                    icon: PhosphorIconsFill.stack,
                    title: 'Стратегии\nпо ордербуку',
                    subtitle: 'Дисбаланс стакана,\nспред, моментум',
                    badge: 'Скоро',
                    badgeColor: Color(0xFF5E6AD2),
                    onTap: () => _showOrderBookModeSelector(),
                  ),
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
              color: pc.surfaceC,
              borderRadius: PfRadius.borderRadiusPill,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PillTab(
                    label: 'Запущенные',
                    count: _activeRuns.length + _activeObRuns.length,
                    isActive: _tabController.index == 0,
                    onTap: () => _tabController.animateTo(0),
                  ),
                  const SizedBox(width: 2),
                  _PillTab(
                    label: 'История по свечам',
                    count: _historyTotal,
                    isActive: _tabController.index == 1,
                    onTap: () => _tabController.animateTo(1),
                  ),
                  const SizedBox(width: 2),
                  _PillTab(
                    label: 'История по OB',
                    count: _obRuns.length,
                    isActive: _tabController.index == 2,
                    onTap: () => _tabController.animateTo(2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: PfSpacing.md),

          // ── Tab Content ─────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildActiveContent(),
                _buildRunsList(
                  runs: _historyRuns,
                  loading: _loadingHistory,
                  emptyIcon: PhosphorIconsFill.clockCounterClockwise,
                  emptyText: 'История пуста',
                  emptySubtext: 'Завершённые стратегии появятся здесь',
                  repository: widget.repository,
                ),
                _buildObRunsList(),
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
    final pc = PfColors.of(context);
    if (loading) {
      return _skeletonList();
    }

    if (runs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              emptyIcon,
              size: 48,
              color: pc.mutedForegroundC.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              emptyText,
              style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC),
            ),
            const SizedBox(height: 4),
            Text(
              emptySubtext,
              style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC.withValues(alpha: 0.6)),
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

  /// Show Order Book mode selector bottom sheet.
  void _showOrderBookModeSelector() {
    final pc = PfColors.of(context);
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(PfSpacing.lg),
        decoration: BoxDecoration(
          color: pc.backgroundC,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
            Text(
              'Режим торговли',
              style: PfTypography.titleLg.copyWith(color: pc.foregroundC),
            ),
            const SizedBox(height: 8),
            Text(
              'Выберите режим для Order Book стратегии',
              style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
            ),
            const SizedBox(height: 24),
            // Virtual mode
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                context.go('/trading/orderbook-wizard');
              },
              child: Container(
                padding: const EdgeInsets.all(PfSpacing.md),
                decoration: BoxDecoration(
                  color: pc.cardC,
                  borderRadius: PfRadius.borderRadiusLg,
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: PfRadius.borderRadiusMd,
                      ),
                      child: Center(
                        child: PhosphorIcon(
                          PhosphorIconsFill.flask,
                          size: 24,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Virtual Mode',
                            style: PfTypography.titleMd.copyWith(
                              color: pc.foregroundC,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Реальные данные Binance, виртуальный баланс.\nБез риска для капитала.',
                            style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: PfColors.success.withValues(alpha: 0.12),
                        borderRadius: PfRadius.borderRadiusPill,
                      ),
                      child: Text(
                        'Доступен',
                        style: PfTypography.caption.copyWith(
                          color: PfColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Real mode — заглушка
            Container(
              padding: const EdgeInsets.all(PfSpacing.md),
              decoration: BoxDecoration(
                color: pc.cardC.withValues(alpha: 0.5),
                borderRadius: PfRadius.borderRadiusLg,
                border: Border.all(color: pc.borderC),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: pc.mutedC,
                      borderRadius: PfRadius.borderRadiusMd,
                    ),
                    child: Center(
                      child: PhosphorIcon(
                        PhosphorIconsFill.coins,
                        size: 24,
                        color: pc.mutedForegroundC,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Real Mode',
                          style: PfTypography.titleMd.copyWith(
                            color: pc.mutedForegroundC,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Реальный баланс и сделки на Binance.\nТребуется API ключ.',
                          style: PfTypography.bodySm.copyWith(
                            color: pc.mutedForegroundC.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: pc.mutedC,
                      borderRadius: PfRadius.borderRadiusPill,
                    ),
                    child: Text(
                      'Скоро',
                      style: PfTypography.caption.copyWith(
                        color: pc.mutedForegroundC,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Active Tab Content (standard + OB) ──────────────────────────────────
  Widget _buildActiveContent() {
    final pc = PfColors.of(context);
    final isLoading = _loadingActive;
    final hasStandard = _activeRuns.isNotEmpty;
    final hasOb = _activeObRuns.isNotEmpty;

    if (isLoading && !hasStandard && !hasOb) {
      return _skeletonList();
    }

    if (!hasStandard && !hasOb) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              PhosphorIconsFill.rocket, size: 48,
              color: pc.mutedForegroundC.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Нет активных стратегий',
              style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC),
            ),
            const SizedBox(height: 4),
            Text(
              'Запустите новую стратегию, чтобы увидеть результаты',
              style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadActiveRuns();
        _pollActiveRuns();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
        children: [
          if (hasStandard) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('📊 По свечам',
                style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC)),
            ),
            ..._activeRuns.map((run) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TradingRunCard(
                run: run,
                scanProgress: _scanProgress[run.id],
                onTap: () => context.go('/trading/run/${run.id}'),
              ),
            )),
            if (hasOb) const SizedBox(height: 12),
          ],
          if (hasOb) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('📗 По ордербуку',
                style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC)),
            ),
            ..._activeObRuns.map((run) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildObRunCard(run),
            )),
          ],
        ],
      ),
    );
  }

  // ── OrderBook History Tab ──────────────────────────────────────────────
  Widget _buildObRunsList() {
    final pc = PfColors.of(context);
    if (_loadingObRuns) {
      return _skeletonList();
    }
    if (_obRuns.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(PhosphorIconsFill.stack, size: 48,
              color: pc.mutedForegroundC.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Нет завершённых OB-запусков',
              style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC)),
            const SizedBox(height: 4),
            Text('Завершённые стратегии по ордербуку появятся здесь',
              style: PfTypography.bodySm.copyWith(
                color: pc.mutedForegroundC.withValues(alpha: 0.6))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadOrderBookRuns,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
        itemCount: _obRuns.length,
        separatorBuilder: (_, __) => const SizedBox(height: PfSpacing.sm),
        itemBuilder: (context, index) => _buildObRunCard(_obRuns[index]),
      ),
    );
  }

  /// Build an OB run card widget (used in both active and history tabs).
  Widget _buildObRunCard(Map<String, dynamic> run) {
    final pc = PfColors.of(context);
    final status = run['status'] as String? ?? 'unknown';
    final pair = run['pair'] as String? ?? 'N/A';
    final strategy = run['strategy'] as String? ?? 'N/A';
    final signalsTotal = (run['signals_total'] as num?)?.toInt() ?? 0;
    final spm = (run['signals_per_minute'] as num?)?.toDouble() ?? 0.0;
    final isActive = status == 'running';
    return PfCard(
      padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
      onTap: () => context.go('/trading/ob-run/${run['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(
                color: isActive ? PfColors.success.withValues(alpha: 0.12) : pc.mutedC,
                borderRadius: PfRadius.borderRadiusMd,
              ),
              child: Center(child: PhosphorIcon(
                isActive ? PhosphorIconsFill.playCircle : PhosphorIconsFill.checkCircle,
                size: 20,
                color: isActive ? PfColors.success : pc.mutedForegroundC,
              )),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pair, style: PfTypography.titleMd.copyWith(color: pc.foregroundC, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('$strategy · ${isActive ? '🟢 Активна' : '⏹️ Завершена'}',
                  style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
              ],
            )),
            if (isActive)
              PfButton(variant: 'outline', size: 'sm', label: '⏹',
                onPressed: () async {
                  final id = run['id'] as int?;
                  if (id != null) {
                    await widget.repository.stopOrderBookRun(id);
                    _loadOrderBookRuns();
                    _loadActiveRuns();
                  }
                },
              ),
          ]),
          // Signal activity row (only for running)
          if (isActive) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: spm > 0 ? PfColors.success : PfColors.warning,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    spm > 0
                        ? '${spm.toStringAsFixed(0)} сигн/мин · $signalsTotal всего'
                        : 'Нет сигналов ($signalsTotal обработано)',
                    style: PfTypography.caption.copyWith(
                      color: spm > 0 ? pc.mutedForegroundC : PfColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Skeleton loader ─────────────────────────────────────────────────────
Widget _skeletonList() {
  return ListView(
    padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
    children: List.generate(3, (_) => Padding(
      padding: const EdgeInsets.only(bottom: PfSpacing.sm),
      child: PfSkeleton(width: double.infinity, height: 88, borderRadius: 12),
    )),
  );
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
    final pc = PfColors.of(context);
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
                    ? pc.foregroundC
                    : pc.mutedForegroundC,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isActive
                    ? pc.foregroundC.withValues(alpha: 0.12)
                    : pc.mutedC,
                borderRadius: PfRadius.borderRadiusPill,
              ),
              child: Text(
                '$count',
                style: PfTypography.caption.copyWith(
                  color: isActive
                      ? pc.foregroundC.withValues(alpha: 0.8)
                      : pc.mutedForegroundC,
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
    final pc = PfColors.of(context);
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
                  translateStrategy(run.strategyName ?? run.config['strategy']),
                  style: PfTypography.titleMd.copyWith(color: pc.foregroundC),
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
                      style: PfTypography.caption.copyWith(color: pc.mutedForegroundC),
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
              _buildScanProgress(scanProgress!, pc)
            else if (run.isVirtual && run.progressPercent != null)
              _buildTimeProgress(run, pc)
            else if (!run.isScanner && !run.isVirtual)
              _buildEstimatedTime(run, pc),
          ],
        ],
      ),
    );
  }

  /// Scan progress — for all_pairs_hammer / all_pairs_inverse_hammer
  Widget _buildScanProgress(Map<String, dynamic> progress, PfColors pc) {
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
                  color: pc.mutedForegroundC,
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
              backgroundColor: pc.surfaceC,
              valueColor: AlwaysStoppedAnimation(PfColors.accentTrading),
              minHeight: 6,
            ),
          ),
          if (etaLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Осталось: $etaLabel',
              style: PfTypography.caption.copyWith(
                color: pc.mutedForegroundC.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Time-based progress — for virtual/real mode with duration
  Widget _buildTimeProgress(TradingRun run, PfColors pc) {
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
                  color: pc.mutedForegroundC,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: PfRadius.borderRadiusPill,
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: pc.surfaceC,
              valueColor: AlwaysStoppedAnimation(PfColors.accentTrading),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  /// Estimated time text — for fast history mode runs
  Widget _buildEstimatedTime(TradingRun run, PfColors pc) {
    final label = run.estimatedTimeLabel ?? '~7 сек';
    return Padding(
      padding: const EdgeInsets.only(top: PfSpacing.sm),
      child: Row(
        children: [
          PhosphorIcon(
            PhosphorIconsFill.clock,
            size: 14,
            color: pc.mutedForegroundC.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Text(
            'Примерное время расчёта: $label',
            style: PfTypography.caption.copyWith(
              color: pc.mutedForegroundC.withValues(alpha: 0.7),
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
    final pc = PfColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PfTypography.caption.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: mono
              ? PfTypography.number.copyWith(color: pc.foregroundC)
              : PfTypography.bodyMd.copyWith(color: pc.foregroundC),
        ),
      ],
    );
  }
}


// ─── Mode Card (выбор типа стратегии) ─────────────────────────────────────
class _ModeCard extends StatelessWidget {
  final PhosphorIconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
    return Material(
      color: pc.cardC,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pc.borderC),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: badgeColor, size: 22),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: pc.foregroundC,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: pc.mutedForegroundC,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
