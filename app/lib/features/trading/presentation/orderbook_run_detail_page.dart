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
  Map<String, dynamic>? _signalStatus;
  bool _loading = true;
  Timer? _signalTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ThemeProvider>().setSection(SectionTheme.trading);
      }
    });
    _loadData();
    // Live status every 3s — обновляет только блоки баланса/сделок/сигналов
    // без полной перезагрузки страницы (не вызывает _loadData)
    _signalTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_run != null && _run!['status'] == 'running') {
        _fetchSignalStatus();
      }
    });
  }

  @override
  void dispose() {
    _signalTimer?.cancel();
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

  Future<void> _fetchSignalStatus() async {
    try {
      final status = await widget.repository.getOrderBookRunStatus(widget.runId);
      if (mounted) setState(() => _signalStatus = status);
    } catch (_) {
      // ignore polling errors silently
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
                      if (_run?['status'] == 'running') ...[
                        const SizedBox(height: PfSpacing.md),
                        _buildSignalActivity(pc),
                      ],
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
    final status = _signalStatus?['running'] == true
        ? 'running'
        : (_run?['status'] as String? ?? 'unknown');
    final isActive = status == 'running';
    // Trade count: live from signalStatus (open_trades), fallback to DB
    final openCount = _signalStatus?['open_trades'] is Map
        ? (_signalStatus!['open_trades'] as Map).length
        : 0;
    final totalTrades = (_run?['total_trades'] as num?)?.toInt() ?? 0;
    final displayTrades = isActive ? openCount : totalTrades;
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
              Expanded(child: _StatCell(label: isActive ? 'Открыто' : 'Сделок', value: '$displayTrades')),
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
    // Live balance from signalStatus, fallback to DB
    final liveBalance = (_signalStatus?['balance'] as num?)?.toDouble();
    final status = _signalStatus?['running'] == true
        ? 'running'
        : (_run?['status'] as String? ?? 'unknown');
    final isActive = status == 'running';
    final displayBalance = liveBalance ?? (_run!['current_balance'] as num?)?.toDouble() ?? startBalance;
    // Total PnL: calculate from live balance, fallback to DB
    final totalPnl = (liveBalance != null && startBalance != null)
        ? liveBalance - startBalance
        : (_run?['total_pnl'] as num?)?.toDouble() ?? 0.0;

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
          _InfoRow(label: 'Открытых позиций', value: '${(liveBalance != null && _signalStatus?['open_trades'] is Map) ? (_signalStatus!['open_trades'] as Map).length : (_run?['total_trades'] ?? 0)}'),
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

    // Подсказки к настройкам
    const configHelpTexts = <String, String>{
      'stoploss': 'Автоматический выход при падении цены на N% от входа. Защищает капитал.',
      'trailing_stop': 'Динамический стоп-лосс, двигающийся за ценой по мере её роста.',
      'trailing_offset': 'Отступ от максимума для активации трейлинг-стопа.',
      'max_hold_seconds': 'Максимальное время удержания позиции в секундах.',
      'confirmation_ticks': 'Количество тиков для подтверждения сигнала входа.',
      'max_spread': 'Максимальный допустимый спред для входа.',
      'cooldown_seconds': 'Пауза между сделками после выхода.',
      'auto_stop_hours': 'Автоматическая остановка стратегии через N часов.',
      'initial_balance': 'Виртуальный стартовый баланс для симуляции.',
      'max_open_trades': 'Максимум одновременных открытых позиций.',
    };

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
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              translateConfigKey(e.key),
                              style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (configHelpTexts.containsKey(e.key))
                            _helpIcon(translateConfigKey(e.key), configHelpTexts[e.key]!),
                        ],
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

  // ── Signal Activity ────────────────────────────────────────────────
  Widget _buildSignalActivity(PfColors pc) {
    final status = _signalStatus;
    final metrics = status?['metrics'] as Map<String, dynamic>? ?? {};
    final signalsTotal = (metrics['signals_generated'] as num?)?.toInt() ?? 0;
    final signalsRejected = (metrics['signals_rejected'] as num?)?.toInt() ?? 0;
    final spm = (metrics['signals_per_minute'] as num?)?.toDouble() ?? 0.0;
    final accepted = signalsTotal - signalsRejected;
    final recent = status?['recent_signals'] as List<dynamic>? ?? [];

    return PfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhosphorIcon(PhosphorIconsFill.waveform, size: 16, color: pc.foregroundC),
              const SizedBox(width: 8),
              Text('Активность сигналов', style: PfTypography.titleMd.copyWith(fontSize: 14, color: pc.foregroundC)),
              const Spacer(),
              _aliveIndicator(spm),
            ],
          ),
          const SizedBox(height: PfSpacing.sm),
          const PfDivider(),
          const SizedBox(height: PfSpacing.sm),
          // Big number
          Text(
            '$signalsTotal',
            style: PfTypography.numberDisplay.copyWith(color: pc.foregroundC, fontSize: 32),
          ),
          Text('сигналов обработано', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
          const SizedBox(height: 12),
          // Speed
          _speedRow(spm, pc),
          const SizedBox(height: 12),
          // Accept/reject bar
          _acceptRejectBar(accepted, signalsRejected, pc),
          const SizedBox(height: 12),
          // Rejection breakdown
          if (signalsRejected > 0) _rejectionBreakdown(metrics, pc),
          const SizedBox(height: 8),
          // Signal log button
          if (recent.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => _showSignalLog(context, recent),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(PhosphorIconsFill.listDashes, size: 14, color: PfColors.mutedForeground),
                    const SizedBox(width: 4),
                    Text(
                      'Последние сигналы (${recent.length})',
                      style: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    PhosphorIcon(PhosphorIconsFill.caretRight, size: 12, color: PfColors.mutedForeground),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _aliveIndicator(double spm) {
    if (spm < 1) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: PfColors.warning, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: PfColors.warning.withValues(alpha: 0.4), blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 6),
          Text('Нет сигналов', style: PfTypography.caption.copyWith(color: PfColors.warning)),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: PfColors.success, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: PfColors.success.withValues(alpha: 0.4), blurRadius: 4)],
          ),
        ),
        const SizedBox(width: 6),
        Text('${spm.toStringAsFixed(0)}/мин', style: PfTypography.caption.copyWith(color: PfColors.success)),
      ],
    );
  }

  Widget _speedRow(double spm, PfColors pc) {
    return Row(
      children: [
        PhosphorIcon(PhosphorIconsFill.lightning, size: 14, color: spm > 0 ? PfColors.success : pc.mutedForegroundC),
        const SizedBox(width: 6),
        Text(
          spm > 0 ? '${spm.toStringAsFixed(0)} сигналов/мин' : 'Нет активности',
          style: PfTypography.bodyMd.copyWith(
            color: spm > 0 ? PfColors.success : pc.mutedForegroundC,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _acceptRejectBar(int accepted, int rejected, PfColors pc) {
    final total = accepted + rejected;
    if (total == 0) {
      return Row(
        children: [
          PhosphorIcon(PhosphorIconsFill.info, size: 14, color: pc.mutedForegroundC),
          const SizedBox(width: 6),
          Text('Ожидание первого сигнала...', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
        ],
      );
    }
    final acceptRatio = accepted / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: PfRadius.borderRadiusPill,
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                Flexible(
                  flex: (acceptRatio * 1000).round().clamp(1, 1000),
                  child: Container(color: PfColors.success),
                ),
                if (rejected > 0)
                  Flexible(
                    flex: ((1 - acceptRatio) * 1000).round().clamp(1, 1000),
                    child: Container(color: PfColors.destructive.withValues(alpha: 0.5)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _dotLabel('✅ Принято', accepted.toString(), PfColors.success, pc),
            const SizedBox(width: 16),
            _dotLabel('❌ Отсеяно', rejected.toString(), PfColors.destructive, pc),
          ],
        ),
        Text(
          '${(accepted / total * 100).toStringAsFixed(2)}% принято',
          style: PfTypography.caption.copyWith(color: pc.mutedForegroundC),
        ),
      ],
    );
  }

  Widget _dotLabel(String label, String value, Color color, PfColors pc) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: PfTypography.bodySm.copyWith(color: pc.foregroundC)),
        const SizedBox(width: 4),
        Text(value, style: PfTypography.bodySm.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _rejectionBreakdown(Map<String, dynamic> metrics, PfColors pc) {
    final breakdown = <MapEntry<String, dynamic>>[];
    const rejectionKeys = {
      'cache_not_warm': 'Кэш',
      'global_stop_filtered': 'Защиты',
      'pairlock_filtered': 'PairLock',
      'has_position_filtered': 'В позиции',
      'rejected_spread': 'Спред',
      'rejected_iceberg': 'Iceberg',
      'rejected_confirm_ticks': 'Тики',
      'rejected_no_signal': 'Нет сигнала',
      'rejected_gatekeeper': 'Вратарь',
      'rejected_wallet': 'Баланс',
    };

    for (final entry in rejectionKeys.entries) {
      final val = (metrics[entry.key] as num?)?.toInt() ?? 0;
      if (val > 0) {
        breakdown.add(MapEntry(entry.value, val));
      }
    }

    if (breakdown.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Разбивка отказов:', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8, runSpacing: 6,
          children: breakdown.map((e) => _reasonChip(e.key, e.value, pc)).toList(),
        ),
      ],
    );
  }

  Widget _reasonChip(String label, int count, PfColors pc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: pc.mutedC.withValues(alpha: 0.5),
        borderRadius: PfRadius.borderRadiusPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: PfTypography.caption.copyWith(color: pc.mutedForegroundC)),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: PfTypography.caption.copyWith(color: pc.foregroundC, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _showSignalLog(BuildContext context, List<dynamic> signals) {
    final pc = PfColors.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx2, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: pc.backgroundC,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: pc.mutedC,
                      borderRadius: PfRadius.borderRadiusPill,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    PhosphorIcon(PhosphorIconsFill.waveform, size: 18, color: pc.foregroundC),
                    const SizedBox(width: 8),
                    Text('Лента сигналов', style: PfTypography.titleMd.copyWith(color: pc.foregroundC, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PfDivider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: signals.length,
                  itemBuilder: (_, i) {
                    final signal = signals[signals.length - 1 - i] as Map<String, dynamic>;
                    final isAccepted = signal['status'] == 'accepted';
                    final signalType = signal['signal_type'] as String? ?? '—';
                    final detail = signal['detail'] as String? ?? '';
                    final timestamp = signal['timestamp'] as String? ?? '';
                    final price = (signal['price'] as num?)?.toDouble() ?? 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PhosphorIcon(
                            isAccepted ? PhosphorIconsFill.checkCircle : PhosphorIconsFill.xCircle,
                            size: 16,
                            color: isAccepted ? PfColors.success : PfColors.destructive.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  signalType.replaceAll('_', ' '),
                                  style: PfTypography.bodyMd.copyWith(color: pc.foregroundC, fontWeight: FontWeight.w500),
                                ),
                                if (detail.isNotEmpty)
                                  Text(detail, style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
                                if (price > 0)
                                  Text('@ ${price.toStringAsFixed(4)}', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _fmtSignalTime(timestamp),
                            style: PfTypography.caption.copyWith(color: pc.mutedForegroundC),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtSignalTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 8 ? iso.substring(11, 19) : iso;
    }
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

  // ── Help Icon ──────────────────────────────────────────────────────
  void _showHelp(String title, String body) {
    final pc = PfColors.of(context);
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
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: pc.mutedC,
                  borderRadius: PfRadius.borderRadiusPill,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(title, style: PfTypography.titleMd.copyWith(color: pc.foregroundC, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(body, style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _helpIcon(String title, String body) {
    return GestureDetector(
      onTap: () => _showHelp(title, body),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(
          Icons.help_outline,
          size: 16,
          color: PfColors.mutedForeground.withValues(alpha: 0.6),
        ),
      ),
    );
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
