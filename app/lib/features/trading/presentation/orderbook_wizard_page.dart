import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/adaptive_scaffold.dart';
import 'package:app/shared/widgets/pf_card.dart';
import 'package:app/shared/widgets/pf_button.dart';
import 'package:app/shared/widgets/pf_badge.dart';
import 'package:app/shared/widgets/pf_divider.dart';
import 'package:app/shared/widgets/responsive_layout.dart';
import 'package:app/features/trading/data/trading_repository.dart';
import 'package:app/features/trading/data/models/trading_pair.dart';
import 'package:dio/dio.dart';
import 'package:app/shared/widgets/error_snackbar.dart';
import 'package:app/features/trading/data/hardcoded_pairs.dart';
import 'package:app/features/trading/data/models/pair_live_data.dart';
import 'package:app/features/trading/data/models/pair_insight.dart';

/// Cтатичные модели данных Order Book визарда.

class _ObStrategyParam {
  final String key;
  final String label;
  final String unit;
  final double defaultValue;
  final double min;
  final double max;
  final int divisions;

  const _ObStrategyParam({
    required this.key,
    required this.label,
    this.unit = '',
    required this.defaultValue,
    this.min = 0,
    this.max = 100,
    this.divisions = 100,
  });
}

class _ObStrategyOption {
  final String name;
  final String label;
  final String description;
  final bool enabled;
  final List<_ObStrategyParam> params;

  const _ObStrategyOption({
    required this.name,
    required this.label,
    required this.description,
    this.enabled = true,
    this.params = const [],
  });
}

const _kObStrategies = [
  _ObStrategyOption(
    name: 'imbalance_scalping',
    label: 'Imbalance Scalping',
    description: 'Ловит дисбаланс Bid/Ask с 3-тик подтверждением',
    params: [
      _ObStrategyParam(
        key: 'imbalance_threshold',
        label: 'Порог дисбаланса',
        unit: '%',
        defaultValue: 0.65, min: 0.55, max: 0.85, divisions: 30,
      ),
      _ObStrategyParam(
        key: 'surge_pct',
        label: 'Всплеск объёма',
        unit: '%',
        defaultValue: 20, min: 5, max: 50, divisions: 45,
      ),
    ],
  ),
  _ObStrategyOption(
    name: 'spread_capture',
    label: 'Spread Capture',
    description: 'Торговля по спреду — расширение/сужение спреда как сигнал',
    params: [
      _ObStrategyParam(
        key: 'min_spread_pct',
        label: 'Мин. спред',
        unit: '%',
        defaultValue: 0.02, min: 0.01, max: 0.1, divisions: 9,
      ),
      _ObStrategyParam(
        key: 'spread_entry_threshold',
        label: 'Порог входа',
        unit: '%',
        defaultValue: 0.03, min: 0.01, max: 0.1, divisions: 9,
      ),
      _ObStrategyParam(
        key: 'spread_exit_threshold',
        label: 'Порог выхода',
        unit: '%',
        defaultValue: 0.01, min: 0.005, max: 0.05, divisions: 9,
      ),
    ],
  ),
  _ObStrategyOption(
    name: 'order_flow_momentum',
    label: 'Order Flow Momentum',
    description: 'Агрессивные market orders как сигнал движения цены',
    params: [
      _ObStrategyParam(
        key: 'flow_threshold_volume',
        label: 'Порог объёма',
        unit: ' USDT',
        defaultValue: 10000, min: 1000, max: 100000, divisions: 99,
      ),
      _ObStrategyParam(
        key: 'min_flow_signals',
        label: 'Мин. сигналов',
        unit: '',
        defaultValue: 2, min: 1, max: 5, divisions: 4,
      ),
      _ObStrategyParam(
        key: 'flow_exit_seconds',
        label: 'Выход через',
        unit: 'с',
        defaultValue: 30, min: 10, max: 120, divisions: 11,
      ),
    ],
  ),
  _ObStrategyOption(
    name: 'ers_scalping',
    label: 'ЕРШ Scalping',
    description: 'Сверхчувствительный скальпинг — ловит даже микро-дисбалансы стакана',
    params: [
      _ObStrategyParam(
        key: 'ers_min_imbalance',
        label: 'Порог дисбаланса',
        unit: '',
        defaultValue: 0.52, min: 0.50, max: 0.65, divisions: 15,
      ),
      _ObStrategyParam(
        key: 'ers_min_profit_pct',
        label: 'Мин. профит',
        unit: '%',
        defaultValue: 0.01, min: 0.005, max: 0.1, divisions: 19,
      ),
      _ObStrategyParam(
        key: 'ers_max_hold_seconds',
        label: 'Max hold',
        unit: 'с',
        defaultValue: 15, min: 3, max: 60, divisions: 19,
      ),
    ],
  ),
];

/// Короткие подписи под шагами.
const _kStepLabels = ['Пара', 'Стратегия', 'Баланс', 'Риски', 'Точность', 'Защиты', 'Сводка'];

/// Иконки шагов.
const _kStepIcons = [
  PhosphorIconsFill.coin,
  PhosphorIconsFill.chartLineUp,
  PhosphorIconsFill.wallet,
  PhosphorIconsFill.shieldCheck,
  PhosphorIconsFill.magnifyingGlassPlus,
  PhosphorIconsFill.lockKey,
  PhosphorIconsFill.listChecks,
];

/// Пресеты «Стандартные» — логически согласованные настройки под каждую стратегию.
const _kStrategyPresets = {
  'imbalance_scalping': {
    'balance': 1000.0,
    'maxOpenTrades': 2,
    'stoploss': -1.0,
    'trailingStop': 0.3,
    'trailingOffset': 0.5,
    'maxHoldSeconds': 120,
    'confirmationTicks': 3,
    'maxSpread': 0.05,
    'cooldownSeconds': 120,
    'autoStopHours': 0,
  },
  'spread_capture': {
    'balance': 5000.0,
    'maxOpenTrades': 3,
    'stoploss': -0.5,
    'trailingStop': 0.5,
    'trailingOffset': 0.3,
    'maxHoldSeconds': 60,
    'confirmationTicks': 2,
    'maxSpread': 0.03,
    'cooldownSeconds': 30,
    'autoStopHours': 2,
  },
  'order_flow_momentum': {
    'balance': 2000.0,
    'maxOpenTrades': 1,
    'stoploss': -1.5,
    'trailingStop': 0.4,
    'trailingOffset': 0.4,
    'maxHoldSeconds': 180,
    'confirmationTicks': 1,
    'maxSpread': 0.08,
    'cooldownSeconds': 60,
    'autoStopHours': 4,
  },
  'ers_scalping': {
    'balance': 50.0,
    'maxOpenTrades': 3,
    'stoploss': -0.5,
    'trailingStop': 0.1,
    'trailingOffset': 0.1,
    'maxHoldSeconds': 15,
    'confirmationTicks': 1,
    'maxSpread': 0.1,
    'cooldownSeconds': 5,
    'autoStopHours': 0,
  },
};

/// Пресеты режимов — 3 режима под каждую стратегию.
const _kStrategyModePresets = {
  'imbalance_scalping': {
    'conservative': {
      'balance': 2000.0,
      'maxOpenTrades': 1,
      'stoploss': -1.5,
      'trailingStop': 0.5,
      'trailingOffset': 0.5,
      'maxHoldSeconds': 180,
      'confirmationTicks': 5,
      'maxSpread': 0.03,
      'cooldownSeconds': 180,
      'autoStopHours': 4,
      'imbalance_threshold': 0.75,
      'surge_pct': 30.0,
    },
    'standard': {
      'balance': 1000.0,
      'maxOpenTrades': 2,
      'stoploss': -1.0,
      'trailingStop': 0.3,
      'trailingOffset': 0.5,
      'maxHoldSeconds': 120,
      'confirmationTicks': 3,
      'maxSpread': 0.05,
      'cooldownSeconds': 120,
      'autoStopHours': 0,
      'imbalance_threshold': 0.65,
      'surge_pct': 20.0,
    },
    'aggressive': {
      'balance': 500.0,
      'maxOpenTrades': 3,
      'stoploss': -0.5,
      'trailingStop': 0.2,
      'trailingOffset': 0.2,
      'maxHoldSeconds': 60,
      'confirmationTicks': 1,
      'maxSpread': 0.08,
      'cooldownSeconds': 30,
      'autoStopHours': 0,
      'imbalance_threshold': 0.58,
      'surge_pct': 10.0,
    },
  },
  'spread_capture': {
    'conservative': {
      'balance': 10000.0,
      'maxOpenTrades': 2,
      'stoploss': -0.3,
      'trailingStop': 0.6,
      'trailingOffset': 0.4,
      'maxHoldSeconds': 120,
      'confirmationTicks': 4,
      'maxSpread': 0.02,
      'cooldownSeconds': 60,
      'autoStopHours': 4,
      'min_spread_pct': 0.05,
      'spread_entry_threshold': 0.06,
      'spread_exit_threshold': 0.02,
    },
    'standard': {
      'balance': 5000.0,
      'maxOpenTrades': 3,
      'stoploss': -0.5,
      'trailingStop': 0.5,
      'trailingOffset': 0.3,
      'maxHoldSeconds': 60,
      'confirmationTicks': 2,
      'maxSpread': 0.03,
      'cooldownSeconds': 30,
      'autoStopHours': 2,
      'min_spread_pct': 0.02,
      'spread_entry_threshold': 0.03,
      'spread_exit_threshold': 0.01,
    },
    'aggressive': {
      'balance': 1000.0,
      'maxOpenTrades': 5,
      'stoploss': -0.3,
      'trailingStop': 0.3,
      'trailingOffset': 0.2,
      'maxHoldSeconds': 30,
      'confirmationTicks': 1,
      'maxSpread': 0.05,
      'cooldownSeconds': 10,
      'autoStopHours': 0,
      'min_spread_pct': 0.01,
      'spread_entry_threshold': 0.02,
      'spread_exit_threshold': 0.005,
    },
  },
  'order_flow_momentum': {
    'conservative': {
      'balance': 5000.0,
      'maxOpenTrades': 1,
      'stoploss': -2.0,
      'trailingStop': 0.8,
      'trailingOffset': 0.6,
      'maxHoldSeconds': 300,
      'confirmationTicks': 3,
      'maxSpread': 0.05,
      'cooldownSeconds': 120,
      'autoStopHours': 6,
      'flow_threshold_volume': 50000.0,
      'min_flow_signals': 3,
      'flow_exit_seconds': 60,
    },
    'standard': {
      'balance': 2000.0,
      'maxOpenTrades': 1,
      'stoploss': -1.5,
      'trailingStop': 0.4,
      'trailingOffset': 0.4,
      'maxHoldSeconds': 180,
      'confirmationTicks': 1,
      'maxSpread': 0.08,
      'cooldownSeconds': 60,
      'autoStopHours': 4,
      'flow_threshold_volume': 10000.0,
      'min_flow_signals': 2,
      'flow_exit_seconds': 30,
    },
    'aggressive': {
      'balance': 500.0,
      'maxOpenTrades': 2,
      'stoploss': -0.8,
      'trailingStop': 0.2,
      'trailingOffset': 0.2,
      'maxHoldSeconds': 60,
      'confirmationTicks': 1,
      'maxSpread': 0.12,
      'cooldownSeconds': 20,
      'autoStopHours': 0,
      'flow_threshold_volume': 2000.0,
      'min_flow_signals': 1,
      'flow_exit_seconds': 15,
    },
  },
  'ers_scalping': {
    'conservative': {
      'balance': 100.0,
      'maxOpenTrades': 2,
      'stoploss': -0.3,
      'trailingStop': 0.15,
      'trailingOffset': 0.15,
      'maxHoldSeconds': 30,
      'confirmationTicks': 1,
      'maxSpread': 0.08,
      'cooldownSeconds': 10,
      'autoStopHours': 0,
      'ers_min_imbalance': 0.58,
      'ers_min_profit_pct': 0.03,
      'ers_max_hold_seconds': 30,
    },
    'standard': {
      'balance': 50.0,
      'maxOpenTrades': 3,
      'stoploss': -0.5,
      'trailingStop': 0.1,
      'trailingOffset': 0.1,
      'maxHoldSeconds': 15,
      'confirmationTicks': 1,
      'maxSpread': 0.1,
      'cooldownSeconds': 5,
      'autoStopHours': 0,
      'ers_min_imbalance': 0.52,
      'ers_min_profit_pct': 0.01,
      'ers_max_hold_seconds': 15,
    },
    'aggressive': {
      'balance': 10.0,
      'maxOpenTrades': 5,
      'stoploss': -0.2,
      'trailingStop': 0.05,
      'trailingOffset': 0.05,
      'maxHoldSeconds': 8,
      'confirmationTicks': 1,
      'maxSpread': 0.15,
      'cooldownSeconds': 3,
      'autoStopHours': 0,
      'ers_min_imbalance': 0.50,
      'ers_min_profit_pct': 0.005,
      'ers_max_hold_seconds': 5,
    },
  },
};


class OrderBookWizardPage extends StatefulWidget {
  final TradingRepository repository;

  const OrderBookWizardPage({super.key, required this.repository});

  @override
  State<OrderBookWizardPage> createState() => _OrderBookWizardPageState();
}

class _OrderBookWizardPageState extends State<OrderBookWizardPage>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  int _previousStep = 0;
  late final AnimationController _slideCtrl;
  TradingRepository get _repository => widget.repository;

  // Step 0: Pair — поиск + infinite scroll
  String _selectedPairSymbol = 'BTCUSDT';
  final List<TradingPair> _loadedPairs = [];
  final TextEditingController _searchPairController = TextEditingController();
  final ScrollController _pairScrollController = ScrollController();
  Timer? _searchTimer;
  int _pairPage = 1;
  bool _hasMorePairs = true;
  bool _loadingPairs = false;
  bool _sortByVolume = false;
  Map<String, PairLiveData> _liveData = {};
  bool _loadingLiveData = false;
  PairInsight? _pairInsight;
  bool _loadingInsight = false;
  Completer<void>? _insightCompleter;

  // Step 1: Strategy
  _ObStrategyOption? _selectedStrategy;
  final Map<String, double> _strategyParams = {};

  // Step 2: Balance
  double _balance = 1000;
  int _maxOpenTrades = 1;

  // Step 3: Risk
  double _stoploss = -1.0;
  double _trailingStop = 0.3;
  double _trailingOffset = 0.5;
  int _maxHoldSeconds = 120;

  // Step 4: Precision
  int _confirmationTicks = 3;
  double _maxSpread = 0.05;

  // Step 5: Protections
  int _cooldownSeconds = 120;
  int _autoStopHours = 0; // 0 = отключено

  // Активный режим пресета на шаге стратегии
  String? _activePresetMode;

  // Data source & trade exchange (Фаза 1-2)
  String _sourceExchange = 'binance';
  String _tradeExchange = 'binance';

  bool _isLoading = false;

  // Live-статус запуска
  int? _lastRunId;
  String _runStatusText = '';
  Timer? _statusTimer;
  bool _runStarted = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _selectedStrategy = _kObStrategies.firstWhere((s) => s.enabled);
    for (final p in _selectedStrategy!.params) {
      _strategyParams[p.key] = p.defaultValue;
    }
    _loadPairs();
    _fetchLiveData();
    // Infinite scroll via scroll controller listener
    _pairScrollController.addListener(() {
      if (!_hasMorePairs || _loadingPairs) return;
      final maxScroll = _pairScrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;
      final threshold = 200.0;
      if (_pairScrollController.position.pixels >= maxScroll - threshold) {
        setState(() => _pairPage++);
        _loadPairs();
      }
    });
    _searchPairController.addListener(() {
      _searchTimer?.cancel();
      _searchTimer = Timer(const Duration(milliseconds: 300), () {
        _loadPairs(refresh: true);
      });
    });
  }

  @override
  void dispose() {
    _stopPolling();
    _slideCtrl.dispose();
    _searchTimer?.cancel();
    _searchPairController.dispose();
    _pairScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
    final theme = Theme.of(context);
    return AdaptiveScaffold(
      title: 'Order Book стратегия',
      currentPath: '/trading/orderbook-wizard',
      showBackButton: true,
      body: ConstrainedContent(
        maxWidth: 720,
        child: Column(
          children: [
            _buildStepProgressBar(theme, pc),
            Expanded(
              child: _buildStepContent(theme, pc),
            ),
            _buildNavigation(theme, pc),
          ],
        ),
      ),
    );
  }

  // ── Step Progress Bar ──────────────────────────────────────────────
  Widget _buildStepProgressBar(ThemeData theme, PfColors pc) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: PfSpacing.md, horizontal: PfSpacing.sm),
      margin: const EdgeInsets.fromLTRB(PfSpacing.lg, PfSpacing.lg, PfSpacing.lg, 0),
      decoration: BoxDecoration(
        color: pc.cardC,
        borderRadius: PfRadius.borderRadiusLg,
        border: Border.all(color: pc.borderC),
      ),
      child: Row(
        children: List.generate(7, (index) {
          final isActive = index == _currentStep;
          final isDone = index < _currentStep;
          return Expanded(
            child: GestureDetector(
              onTap: () => _onStepTapped(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Step dot
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone
                            ? PfColors.success
                            : isActive
                                ? theme.colorScheme.primary
                                : pc.mutedC,
                      ),
                      child: Center(
                        child: isDone
                            ? PhosphorIcon(
                                PhosphorIconsFill.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : Text(
                                '${index + 1}',
                                style: PfTypography.caption.copyWith(
                                  color: isActive
                                      ? theme.colorScheme.onPrimary
                                      : pc.mutedForegroundC,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _kStepLabels[index],
                      style: PfTypography.caption.copyWith(
                        color: isActive
                            ? theme.colorScheme.primary
                            : isDone
                                ? PfColors.success
                                : pc.mutedForegroundC,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _onStepTapped(int index) {
    // Не даём перепрыгивать вперёд больше чем на 1 шаг
    if (index <= _currentStep + 1 && index != _currentStep) {
      _previousStep = _currentStep;
      setState(() => _currentStep = index);
      _slideCtrl.forward(from: 0);
    }
  }

  // ── Polling статуса запуска ──────────────────────────────────────
  void _startPolling(int runId) {
    _lastRunId = runId;
    _runStarted = true;
    _runStatusText = '⏳ Подключение к Binance...';
    setState(() {});
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollRunStatus();
    });
  }

  void _stopPolling() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  Future<void> _pollRunStatus() async {
    if (_lastRunId == null) return;
    try {
      final run = await _repository.getOrderBookRun(_lastRunId!);
      if (!mounted) return;
      final status = run['status'] as String? ?? 'unknown';
      if (status == 'running') {
        _runStatusText = '✅ Торгует';
      } else if (status == 'stopped') {
        _runStatusText = '⏹️ Остановлен';
        _stopPolling();
      } else if (status == 'error') {
        _runStatusText = '❌ Ошибка: ${run['error'] ?? 'неизвестная'}';
        _stopPolling();
      } else {
        _runStatusText = '🔄 Статус: $status';
      }
      setState(() {});
    } catch (_) {
      // ignore polling errors silently
    }
  }

  // ── Animated Step Content ────────────────────────────────────────

  Future<void> _loadPairs({bool refresh = false}) async {
    if (_loadingPairs) return;
    if (refresh) {
      _loadedPairs.clear();
      _pairPage = 1;
      _hasMorePairs = true;
    }
    setState(() => _loadingPairs = true);
    // Локальная фильтрация из hardcoded_pairs.dart — без API-запроса
    final search = _searchPairController.text.trim().toUpperCase();
    var filtered = allTradingPairs.where((p) {
      if (search.isEmpty) return true;
      return p.symbol.contains(search) || p.base.contains(search);
    }).toList();
    if (!mounted) return;
    // Сортировка по объёму, если включена и данные загружены
    if (_sortByVolume && _liveData.isNotEmpty) {
      filtered.sort((a, b) {
        final va = _liveData[a.symbol]?.volume ?? 0;
        final vb = _liveData[b.symbol]?.volume ?? 0;
        return vb.compareTo(va);
      });
    }
    setState(() {
      _loadedPairs
        ..clear()
        ..addAll(filtered);
      _hasMorePairs = false;
      _loadingPairs = false;
    });
  }

  Future<void> _fetchLiveData() async {
    if (_loadingLiveData) return;
    setState(() => _loadingLiveData = true);
    try {
      final liveData = await _repository.getPairsLive();
      if (mounted) {
        setState(() {
          _liveData = liveData;
          _loadingLiveData = false;
        });
        // Пересортировать по объёму, если сортировка включена
        if (_sortByVolume && _loadedPairs.isNotEmpty) {
          setState(() {
            _loadedPairs.sort((a, b) {
              final va = liveData[a.symbol]?.volume ?? 0;
              final vb = liveData[b.symbol]?.volume ?? 0;
              return vb.compareTo(va);
            });
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLiveData = false);
    }
  }

  Future<void> _fetchPairInsight(String symbol) async {
    if (_loadingInsight) {
      // Уже грузится — дожидаемся завершения
      await _insightCompleter?.future;
      return;
    }
    _insightCompleter = Completer<void>();
    setState(() => _loadingInsight = true);
    try {
      final insight = await _repository.getPairInsight(symbol);
      if (mounted) {
        setState(() {
          _pairInsight = insight;
          _loadingInsight = false;
        });
      }
    } catch (e) {
      debugPrint('[WIZARD] _fetchPairInsight error for $symbol: $e');
      if (mounted) setState(() => _loadingInsight = false);
    } finally {
      _insightCompleter?.complete();
      _insightCompleter = null;
    }
  }

  // ── Helper: иконка "?" с подсказкой ──────────────────────────────

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

  // ── «Стандартные» — сброс всех полей к пресету ──────────────────
  void _applyDefaults() {
    final preset = _kStrategyPresets[_selectedStrategy?.name ?? ''];
    if (preset == null) return;
    setState(() {
      _balance = preset['balance'] as double;
      _maxOpenTrades = preset['maxOpenTrades'] as int;
      _stoploss = preset['stoploss'] as double;
      _trailingStop = preset['trailingStop'] as double;
      _trailingOffset = preset['trailingOffset'] as double;
      _maxHoldSeconds = preset['maxHoldSeconds'] as int;
      _confirmationTicks = preset['confirmationTicks'] as int;
      _maxSpread = preset['maxSpread'] as double;
      _cooldownSeconds = preset['cooldownSeconds'] as int;
      _autoStopHours = preset['autoStopHours'] as int;
      // Сброс параметров стратегии к дефолтным
      _strategyParams.clear();
      for (final p in _selectedStrategy?.params ?? []) {
        _strategyParams[p.key] = p.defaultValue;
      }
    });
  }

  /// Применить пресет режима (консервативный / стандарт / агрессивный).
  void _applyModePreset(String mode) {
    final preset = _kStrategyModePresets[_selectedStrategy?.name ?? '']?[mode];
    if (preset == null) return;
    setState(() {
      _balance = (preset['balance'] as num).toDouble();
      _maxOpenTrades = (preset['maxOpenTrades'] as num).toInt();
      _stoploss = (preset['stoploss'] as num).toDouble();
      _trailingStop = (preset['trailingStop'] as num).toDouble();
      _trailingOffset = (preset['trailingOffset'] as num).toDouble();
      _maxHoldSeconds = (preset['maxHoldSeconds'] as num).toInt();
      _confirmationTicks = (preset['confirmationTicks'] as num).toInt();
      _maxSpread = (preset['maxSpread'] as num).toDouble();
      _cooldownSeconds = (preset['cooldownSeconds'] as num).toInt();
      _autoStopHours = (preset['autoStopHours'] as num).toInt();
      // Параметры стратегии
      _strategyParams.clear();
      for (final p in _selectedStrategy?.params ?? []) {
        final val = preset[p.key];
        _strategyParams[p.key] = (val is num) ? val.toDouble() : p.defaultValue;
      }
      _activePresetMode = mode;
    });
  }

  /// Динамический расчёт параметров стратегии под текущее состояние рынка.
  /// Использует PairInsight (volatility, volume, spread) для каждой стратегии.
  void _applyDynamicParams(String strategyName, PairInsight insight) {
    final vol = insight.volatility24h;
    final volume = insight.volume24h;
    final spread = insight.spread;

    // ── Общие параметры (для всех стратегий) ──
    // Баланс: выше волатильность → больше баланс
    double balance;
    if (vol > 5.0) {
      balance = 2000.0;
    } else if (vol > 2.0) {
      balance = 1000.0;
    } else {
      balance = 500.0;
    }

    // Тики подтверждения: выше волатильность → больше тиков (фильтр шума)
    int confirmationTicks;
    if (vol > 5.0) {
      confirmationTicks = 3;
    } else if (vol > 2.0) {
      confirmationTicks = 2;
    } else {
      confirmationTicks = 1;
    }

    // Макс. спред: выше волатильность → шире спред (проскальзывание)
    double maxSpread;
    if (vol > 5.0) {
      maxSpread = 0.08;
    } else if (vol > 2.0) {
      maxSpread = 0.05;
    } else {
      maxSpread = 0.03;
    }

    // Кулдаун: выше волатильность → короче (чаще входы)
    int cooldownSeconds;
    if (vol > 5.0) {
      cooldownSeconds = 30;
    } else if (vol > 2.0) {
      cooldownSeconds = 60;
    } else {
      cooldownSeconds = 120;
    }

    // Стоп-лосс: выше волатильность → шире стоп
    double stoploss;
    if (vol > 5.0) {
      stoploss = -1.5;
    } else if (vol > 2.0) {
      stoploss = -1.0;
    } else {
      stoploss = -0.5;
    }

    // Auto-stop: выше волатильность → короче (безопасность)
    int autoStopHours;
    if (vol > 5.0) {
      autoStopHours = 2;
    } else if (vol > 2.0) {
      autoStopHours = 4;
    } else {
      autoStopHours = 0;
    }

    // Max open trades: от волатильности
    int maxOpenTrades;
    if (vol > 5.0) {
      maxOpenTrades = 3;
    } else if (vol > 2.0) {
      maxOpenTrades = 2;
    } else {
      maxOpenTrades = 1;
    }

    // ── Специфичные параметры для каждой стратегии ──
    final strategyParams = <String, double>{};

    switch (strategyName) {
      case 'imbalance_scalping':
        // Порог дисбаланса: выше объём → ниже порог (больше сигналов)
        double imbalanceThreshold;
        if (volume > 200_000_000) {
          imbalanceThreshold = 0.60;
        } else if (volume > 50_000_000) {
          imbalanceThreshold = 0.65;
        } else {
          imbalanceThreshold = 0.70;
        }
        strategyParams['imbalance_threshold'] = imbalanceThreshold;

        // Всплеск объёма: выше волатильность → выше порог всплеска
        double surgePct;
        if (vol > 5.0) {
          surgePct = 30.0;
        } else if (vol > 2.0) {
          surgePct = 20.0;
        } else {
          surgePct = 10.0;
        }
        strategyParams['surge_pct'] = surgePct;
        break;

      case 'spread_capture':
        // Мин. спред = текущий спред × 2 (с запасом), но не ниже 0.01
        double minSpread = (spread * 2).clamp(0.01, 0.1);
        strategyParams['min_spread_pct'] = minSpread;

        // Порог входа = мин. спред × 1.5
        strategyParams['spread_entry_threshold'] = (minSpread * 1.5).clamp(0.01, 0.1);

        // Порог выхода = мин. спред × 0.5
        strategyParams['spread_exit_threshold'] = (minSpread * 0.5).clamp(0.005, 0.05);

        // Баланс для spread: выше объём → больше баланс
        if (volume > 200_000_000) {
          balance = 5000.0;
        } else if (volume > 50_000_000) {
          balance = 3000.0;
        } else {
          balance = 1000.0;
        }
        break;

      case 'order_flow_momentum':
        // Порог объёма = среднедневной объём / 100000 (для ETH 682M → 6820)
        double flowThreshold = (volume / 100000).clamp(1000, 50000);
        strategyParams['flow_threshold_volume'] = flowThreshold;

        // Мин. сигналов: выше объём → меньше сигналов (чище)
        if (volume > 200_000_000) {
          strategyParams['min_flow_signals'] = 1;
        } else {
          strategyParams['min_flow_signals'] = 2;
        }

        // Выход: выше волатильность → быстрее выход
        if (vol > 5.0) {
          strategyParams['flow_exit_seconds'] = 15;
        } else {
          strategyParams['flow_exit_seconds'] = 30;
        }

        // Баланс для momentum: от объёма
        if (volume > 500_000_000) {
          balance = 2000.0;
        } else if (volume > 100_000_000) {
          balance = 1000.0;
        } else {
          balance = 500.0;
        }
        break;

      case 'ers_scalping':
        // Порог дисбаланса: выше волатильность → ниже порог (чувствительнее)
        double ersImbalance;
        if (vol > 5.0) {
          ersImbalance = 0.50;
        } else if (vol > 2.0) {
          ersImbalance = 0.52;
        } else {
          ersImbalance = 0.55;
        }
        strategyParams['ers_min_imbalance'] = ersImbalance;

        // Мин. профит: от спреда (узкий спред → малый профит, частые входы)
        double ersProfit;
        if (spread < 0.02) {
          ersProfit = 0.005;
        } else if (spread < 0.05) {
          ersProfit = 0.01;
        } else {
          ersProfit = 0.02;
        }
        strategyParams['ers_min_profit_pct'] = ersProfit;

        // Max hold: выше волатильность → короче
        if (vol > 5.0) {
          strategyParams['ers_max_hold_seconds'] = 8;
        } else {
          strategyParams['ers_max_hold_seconds'] = 15;
        }

        // Баланс для ЕРШ: минимальный, стратегия на микро-профитах
        balance = 50.0;
        break;
    }

    setState(() {
      _balance = balance;
      _maxOpenTrades = maxOpenTrades;
      _stoploss = stoploss;
      _maxHoldSeconds = vol > 5.0 ? 60 : (vol > 2.0 ? 120 : 180);
      _confirmationTicks = confirmationTicks;
      _maxSpread = maxSpread;
      _cooldownSeconds = cooldownSeconds;
      _autoStopHours = autoStopHours;
      _trailingStop = vol > 5.0 ? 0.2 : (vol > 2.0 ? 0.3 : 0.5);
      _trailingOffset = vol > 5.0 ? 0.2 : (vol > 2.0 ? 0.3 : 0.5);
      // Параметры стратегии
      _strategyParams.addAll(strategyParams);
      _activePresetMode = 'recommended'; // подсвечиваем кнопку "Рекоменд."
    });
  }

  /// Рекомендации — подбор режима по рынку через PairInsight.
  /// Если стратегия уже выбрана — не меняет её, подбирает только режим.
  /// Если стратегия не выбрана — подбирает и стратегию, и режим.
  Future<void> _applyRecommendations() async {
    if (_selectedPairSymbol.isEmpty) return;
    // Загружаем insight если ещё нет
    if (_pairInsight == null) {
      await _fetchPairInsight(_selectedPairSymbol);
      if (!mounted) return;
    }
    final insight = _pairInsight;
    if (insight == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Не удалось загрузить рекомендации. Проверьте соединение.'),
            backgroundColor: PfColors.destructive,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final vol = insight.volatility24h;

    // Режим выбираем по волатильности
    String bestMode;
    if (vol > 5.0) {
      bestMode = 'aggressive';
    } else if (vol > 2.0) {
      bestMode = 'standard';
    } else {
      bestMode = 'conservative';
    }

    if (_selectedStrategy != null) {
      // Стратегия уже выбрана — динамический расчёт параметров под рынок
      _applyDynamicParams(_selectedStrategy!.name, insight);
      return;
    }

    // Стратегия не выбрана — подбираем обе
    final volume = insight.volume24h;
    final isHighVol = volume > 50_000_000;

    String bestStrategy;
    if (vol > 5.0) {
      // Высокая волатильность → imbalance_scalping aggressive или ers aggressive
      if (insight.spread < 0.05) {
        bestStrategy = 'ers_scalping';
      } else {
        bestStrategy = 'imbalance_scalping';
      }
    } else if (vol < 1.0 && isHighVol) {
      bestStrategy = 'spread_capture';
    } else if (volume > 100_000_000) {
      bestStrategy = 'order_flow_momentum';
    } else if (vol > 3.0 && insight.spread < 0.08) {
      bestStrategy = 'ers_scalping';
    } else {
      bestStrategy = 'imbalance_scalping';
    }

    // Находим стратегию в списке и выбираем её
    final target = _kObStrategies.cast<_ObStrategyOption?>().firstWhere(
      (s) => s!.name == bestStrategy,
      orElse: () => null,
    );
    if (target == null) return;

    // Выбираем стратегию
    _strategyParams.clear();
    for (final p in target.params) {
      _strategyParams[p.key] = p.defaultValue;
    }
    setState(() => _selectedStrategy = target);

    // Применяем пресет
    _applyModePreset(bestMode);
    // Подсвечиваем кнопку "Рекоменд." (поверх пресета)
    setState(() => _activePresetMode = 'recommended');
  }

  /// Сброс активного пресета при ручном изменении любого параметра.
  void _onAnyParamChanged() {
    if (_activePresetMode != null) {
      _activePresetMode = null;
    }
  }

  Widget _defaultsButton(ThemeData theme) {
    return GestureDetector(
      onTap: _applyDefaults,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: PfRadius.borderRadiusMd,
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(PhosphorIconsFill.arrowCounterClockwise, size: 13, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              'Стандартные',
              style: PfTypography.caption.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Панель выбора режима пресетов (Консерв / Стандарт / Агрессив / Рекоменд).
  Widget _buildPresetBar(ThemeData theme, PfColors pc) {
    final isSelected = <String, bool>{
      'conservative': _activePresetMode == 'conservative',
      'standard': _activePresetMode == 'standard',
      'aggressive': _activePresetMode == 'aggressive',
      'recommended': _activePresetMode == 'recommended',
    };

    Widget _modeBtn(String label, PhosphorIconData icon, String mode) {
      final active = isSelected[mode] ?? false;
      return GestureDetector(
        onTap: () {
          if (mode == 'recommended') {
            _applyRecommendations();
          } else {
            _applyModePreset(mode);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : pc.surfaceC,
            borderRadius: PfRadius.borderRadiusMd,
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary
                  : pc.borderC,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                icon,
                size: 14,
                color: active
                    ? theme.colorScheme.primary
                    : pc.mutedForegroundC,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: PfTypography.caption.copyWith(
                  color: active
                      ? theme.colorScheme.primary
                      : pc.mutedForegroundC,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Мобилка (<500px): Wrap в 2 ряда, десктоп: Row
        final isMobile = constraints.maxWidth < 500;
        final buttons = [
          _modeBtn('Консерв.', PhosphorIconsFill.shieldCheck, 'conservative'),
          _modeBtn('Стандарт', PhosphorIconsFill.lightning, 'standard'),
          _modeBtn('Агрессив', PhosphorIconsFill.fire, 'aggressive'),
          _modeBtn('Рекоменд.', PhosphorIconsFill.robot, 'recommended'),
        ];

        if (isMobile) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: buttons,
          );
        }
        return Row(
          children: [
            ...buttons.expand((b) => [b, const SizedBox(width: 8)]),
          ],
        );
      },
    );
  }

  // ── Иконка криптопары ────────────────────────────────────────────
  Widget _pairIcon(String base, ThemeData theme) {
    final symbol = base.toLowerCase();
    // Пробуем загрузить из assets, fallback на первую букву
    return Image.asset(
      'assets/icons/crypto/$symbol.png',
      width: 40,
      height: 40,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Center(
        child: Text(
          base.isNotEmpty ? base[0].toUpperCase() : '?',
          style: PfTypography.titleMd.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Step Content Router ────────────────────────────────────────────
  Widget _buildStepContent(ThemeData theme, PfColors pc) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (child, animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.3, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
      // Step 0 (Pair selection) — sticky search + scrollable list
      // Other steps — single scroll view
      child: _currentStep == 0
          ? _buildStepContentScrollable(theme, pc, key: const ValueKey('step_0'))
          : SingleChildScrollView(
              key: ValueKey('step_$_currentStep'),
              padding: const EdgeInsets.fromLTRB(PfSpacing.lg, 0, PfSpacing.lg, PfSpacing.lg),
              child: _buildStepWidget(theme, pc),
            ),
    );
  }

  /// Step 0 only: sticky header (title + search) + scrollable pair list
  Widget _buildStepContentScrollable(ThemeData theme, PfColors pc, {Key? key}) {
    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: Column(
            children: [
              // ── Fixed header: title + description + search ──
              Padding(
                padding: const EdgeInsets.fromLTRB(PfSpacing.lg, PfSpacing.lg, PfSpacing.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PhosphorIcon(_kStepIcons[0], size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Выберите пару', style: PfTypography.titleLg.copyWith(color: pc.foregroundC)),
                        const Spacer(),
                        _helpIcon('Выбор пары', 'Поиск среди 430+ USDT торговых пар с Binance. Выберите пару для Order Book стратегии. Можно фильтровать по названию в поле поиска.'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Поиск и выбор торговой пары для Order Book стратегии',
                      style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
                    ),
                    const SizedBox(height: PfSpacing.md),

                    // ── Exchange selector: source + trade ──
                    Container(
                      padding: const EdgeInsets.all(PfSpacing.sm),
                      decoration: BoxDecoration(
                        color: pc.surfaceC,
                        borderRadius: PfRadius.borderRadiusMd,
                        border: Border.all(color: pc.borderC),
                      ),
                      child: Column(
                        children: [
                          // Source exchange
                          Row(
                            children: [
                              PhosphorIcon(PhosphorIconsFill.cloudArrowDown,
                                size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('📡 Данные',
                                style: PfTypography.bodySm.copyWith(
                                  color: pc.mutedForegroundC,
                                  fontWeight: FontWeight.w500,
                                )),
                              const Spacer(),
                              _buildExchangeDropdown(
                                value: _sourceExchange,
                                items: const ['binance', 'bybit'],
                                onChanged: (v) {
                                  setState(() => _sourceExchange = v);
                                  // If source changes and trade was same, keep in sync
                                  // otherwise leave trade as-is
                                },
                                pc: pc,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Divider
                          Container(height: 1, color: pc.borderC),
                          const SizedBox(height: 6),
                          // Trade exchange
                          Row(
                            children: [
                              PhosphorIcon(PhosphorIconsFill.coins,
                                size: 16, color: PfColors.success),
                              const SizedBox(width: 8),
                              Text('💱 Торговля',
                                style: PfTypography.bodySm.copyWith(
                                  color: pc.mutedForegroundC,
                                  fontWeight: FontWeight.w500,
                                )),
                              const Spacer(),
                              _buildExchangeDropdown(
                                value: _tradeExchange,
                                items: const ['binance', 'bybit'],
                                onChanged: (v) {
                                  setState(() => _tradeExchange = v);
                                },
                                pc: pc,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: PfSpacing.sm),
                    // Search field
                    Container(
                      decoration: BoxDecoration(
                        color: pc.surfaceC,
                        borderRadius: PfRadius.borderRadiusMd,
                        border: Border.all(color: pc.borderC),
                      ),
                      child: TextField(
                        controller: _searchPairController,
                        style: PfTypography.bodyMd.copyWith(color: pc.foregroundC),
                        decoration: InputDecoration(
                          hintText: 'Поиск пары...',
                          hintStyle: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          prefixIcon: PhosphorIcon(
                            PhosphorIconsFill.magnifyingGlass,
                            size: 18,
                            color: pc.mutedForegroundC,
                          ),
                          suffixIcon: _searchPairController.text.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _searchPairController.clear();
                                    _loadPairs(refresh: true);
                                  },
                                  child: PhosphorIcon(
                                    PhosphorIconsFill.x,
                                    size: 16,
                                    color: pc.mutedForegroundC,
                                  ),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 8),
                // Sort toggle
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _sortByVolume = !_sortByVolume;
                          _loadedPairs.clear();
                          _pairPage = 1;
                          _hasMorePairs = true;
                        });
                        _loadPairs();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _sortByVolume
                              ? theme.colorScheme.primary.withValues(alpha: 0.15)
                              : pc.surfaceC,
                          borderRadius: PfRadius.borderRadiusMd,
                          border: Border.all(
                            color: _sortByVolume
                                ? theme.colorScheme.primary
                                : pc.borderC,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PhosphorIcon(
                              _sortByVolume
                                  ? PhosphorIconsFill.arrowDown
                                  : PhosphorIconsFill.arrowDown,
                              size: 14,
                              color: _sortByVolume
                                  ? theme.colorScheme.primary
                                  : pc.mutedForegroundC,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _sortByVolume ? 'По объёму' : 'По умолчанию',
                              style: PfTypography.bodySm.copyWith(
                                color: _sortByVolume
                                    ? theme.colorScheme.primary
                                    : pc.mutedForegroundC,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          // ── Scrollable pair list ──
          Expanded(
                child: _buildPairList(theme, pc),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Scrollable pair list with infinite scroll
  Widget _buildPairList(ThemeData theme, PfColors pc) {
    if (_loadingPairs && _loadedPairs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      controller: _pairScrollController,
      padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
      itemCount: _loadedPairs.length + 1, // +1 for loader/end-of-list
      itemBuilder: (ctx, index) {
        // Loader trigger at the end
        if (index == _loadedPairs.length) {
          if (_hasMorePairs) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          } else {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  'Все пары загружены (${_loadedPairs.length})',
                  style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
                ),
              ),
            );
          }
        }

        final pair = _loadedPairs[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: PfCard(
            variant: _selectedPairSymbol == pair.symbol ? 'trading' : 'default',
            onTap: () => setState(() {
              _selectedPairSymbol = pair.symbol;
              _pairInsight = null;
            }),
            padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _selectedPairSymbol == pair.symbol
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : pc.mutedC,
                    borderRadius: PfRadius.borderRadiusMd,
                  ),
                  child: ClipRRect(
                    borderRadius: PfRadius.borderRadiusMd,
                    child: _pairIcon(pair.base, theme),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pair.symbol,
                        style: PfTypography.titleMd.copyWith(
                          color: pc.foregroundC,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (pair.base.isNotEmpty)
                        Text(
                          '${pair.base}/${pair.quote}',
                          style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
                        ),
                    ],
                  ),
                ),
                // Live data column
                if (_loadingLiveData)
                  _obSkeletonColumn(theme)
                else
                  ...[
                    Builder(builder: (ctx) {
                      final ld = _liveData[pair.symbol];
                      if (ld == null) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _obFormatPrice(ld.price),
                            style: PfTypography.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _obFormatChange(ld.change24h),
                                style: PfTypography.bodySm.copyWith(
                                  color: ld.change24h >= 0
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFFEF4444),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _obFormatVolume(ld.volume),
                                style: PfTypography.caption.copyWith(
                                  color: pc.mutedForegroundC,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }),
                    const SizedBox(width: 12),
                    if (_selectedPairSymbol == pair.symbol)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStepWidget(ThemeData theme, PfColors pc) {
    switch (_currentStep) {
      case 0: return _buildStepPair(theme, pc);
      case 1: return _buildStepStrategy(theme, pc);
      case 2: return _buildStepBalance(theme, pc);
      case 3: return _buildStepRisk(theme, pc);
      case 4: return _buildStepPrecision(theme, pc);
      case 5: return _buildStepProtections(theme, pc);
      case 6: return _buildStepSummary(theme, pc);
      default: return const SizedBox();
    }
  }

  // ── Кастомный слайдер ──────────────────────────────────────────────
  Widget _buildCustomSlider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChange,
    required ThemeData theme,
    required PfColors pc,
    String? label,
    bool destructive = false,
  }) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
        activeTrackColor: destructive ? PfColors.destructive : theme.colorScheme.primary,
        inactiveTrackColor: pc.mutedC,
        thumbColor: destructive ? PfColors.destructive : theme.colorScheme.primary,
        overlayColor: (destructive ? PfColors.destructive : theme.colorScheme.primary)
            .withValues(alpha: 0.12),
        valueIndicatorColor: destructive ? PfColors.destructive : theme.colorScheme.primary,
        valueIndicatorTextStyle: PfTypography.caption.copyWith(color: Colors.white),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label ?? value.toStringAsFixed(value < 1 ? 2 : 0),
        onChanged: onChange,
      ),
    );
  }

  // ── Strategy tips per step ─────────────────────────────────────────

  static const Map<String, Map<int, String>> _strategyTips = {
    'imbalance_scalping': {
      2: '💡 Imbalance Scalping: начните с \$500–\$2000, 1–2 макс. сделки. Частые входы требуют небольшого баланса.',
      3: '💡 Imbalance Scalping: стоп-лосс –1% до –1.5%, трейлинг 0.3–0.5%. Агрессивные входы — без широких стопов.',
      4: '💡 Imbalance Scalping: 1–2 тика подтверждения, макс. спред 0.05–0.10%. Ловите резкие движения.',
      5: '💡 Imbalance Scalping: кулдаун 30–60с, авто-стоп 2–4ч. Быстрые входы = частые паузы.',
    },
    'spread_capture': {
      2: '💡 Spread Capture: \$2000–\$5000 оптимально. Для глубины стакана нужен запас.',
      3: '💡 Spread Capture: стоп-лосс –0.5% до –1% (очень узкий), трейлинг 0.4–0.8%.',
      4: '💡 Spread Capture: 2–3 тика подтверждения (терпеливо), макс. спред 0.02–0.05%.',
      5: '💡 Spread Capture: кулдаун 10–30с (частые ре-входы), авто-стоп 1–2ч.',
    },
    'order_flow_momentum': {
      2: '💡 Order Flow Momentum: \$1000–\$3000. Баланс должен пережить накопление моментума.',
      3: '💡 Order Flow Momentum: стоп-лосс –1.5% до –2.5%, трейлинг 0.5–1%. Моментум требует простора.',
      4: '💡 Order Flow Momentum: 1–2 тика подтверждения, макс. спред 0.08–0.15%.',
      5: '💡 Order Flow Momentum: кулдаун 60–120с, авто-стоп 3–6ч. Моментум строится не мгновенно.',
    },
    'ers_scalping': {
      2: '💡 ЕРШ Scalping: от \$10! Микро-сделки, частые входы. Баланс почти не нужен — прибыль от частоты.',
      3: '💡 ЕРШ Scalping: стоп-лосс –0.5% макс, трейлинг 0.1–0.2%. Жёсткие стопы — микро-движения не прощают.',
      4: '💡 ЕРШ Scalping: без подтверждения, макс. спред 0.05–0.10%. Вход по первому дисбалансу.',
      5: '💡 ЕРШ Scalping: кулдаун 3–10с (мгновенный ре-вход), авто-стоп выкл — крутится бесконечно.',
    },
  };

  Widget _buildStepTip(int step, PfColors pc) {
    if (_selectedStrategy == null) return const SizedBox.shrink();
    final tip = _strategyTips[_selectedStrategy!.name]?[step];
    if (tip == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: pc.surfaceC,
          borderRadius: PfRadius.borderRadiusMd,
          border: Border.all(color: pc.borderC),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💡', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tip.replaceFirst('💡 ', ''),
                style: PfTypography.bodySm.copyWith(color: pc.foregroundC),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Подсказка о минимальном балансе для выбранной стратегии.
  Widget _buildMinBalanceHint(ThemeData theme, PfColors pc) {
    if (_selectedStrategy == null) return const SizedBox.shrink();

    // Минимальный рекомендуемый баланс для каждой стратегии
    final minBalances = {
      'imbalance_scalping': 100.0,
      'spread_capture': 500.0,
      'order_flow_momentum': 200.0,
      'ers_scalping': 10.0,
    };

    final minBalance = minBalances[_selectedStrategy!.name] ?? 100.0;
    final perTrade = (minBalance / _maxOpenTrades).toStringAsFixed(2);

    // Если текущий баланс ниже minBalance — подсветить красным
    final isLow = _balance < minBalance;
    final borderColor = isLow ? PfColors.destructive : pc.borderC;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isLow ? PfColors.destructive.withValues(alpha: 0.08) : pc.surfaceC,
          borderRadius: PfRadius.borderRadiusMd,
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhosphorIcon(
              isLow ? PhosphorIconsFill.warning : PhosphorIconsFill.info,
              size: 16,
              color: isLow ? PfColors.destructive : pc.mutedForegroundC,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isLow
                    ? '⚠ Минимальный баланс для $_selectedStrategyLabel: \$${minBalance.toStringAsFixed(0)}. '
                        'Текущий баланс \$${_balance.toStringAsFixed(0)} может быть недостаточен. '
                        'На сделку: ~\$$perTrade'
                    : '💡 Минимальный баланс для $_selectedStrategyLabel: \$${minBalance.toStringAsFixed(0)}. '
                        'На сделку: ~\$$perTrade',
                style: PfTypography.bodySm.copyWith(
                  color: isLow ? PfColors.destructive : pc.foregroundC,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _selectedStrategyLabel =>
      _selectedStrategy?.label ?? 'стратегии';

  // ── Step 0: Pair (old layout) ──
  Widget _buildStepPair(ThemeData theme, PfColors pc) {
    return const SizedBox.shrink();
  }

  // ── Insight card ───────────────────────────────────────────────────

  Widget _buildInsightCard(PairInsight insight, ThemeData theme, PfColors pc) {
    final symbol = insight.symbol.replaceAll('USDT', '/USDT');
    return PfCard(
      variant: 'default',
      padding: const EdgeInsets.all(PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PhosphorIcon(PhosphorIconsFill.lightbulb, size: 18, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Text('Рекомендация для $symbol',
                  style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _insightStat('Объём 24ч', _obFormatVolume(insight.volume24h), pc),
              const SizedBox(width: 16),
              _insightStat('Волатильность', '${insight.volatility24h.toStringAsFixed(1)}%', pc),
              const SizedBox(width: 16),
              _insightStat('Цена', _obFormatPrice(insight.price), pc),
            ],
          ),
          const SizedBox(height: 12),
          ...insight.recommendedStrategies.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                _medalIcon(s.score),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${s.label}  ${(s.score * 100).toInt()}%',
                          style: PfTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.w600,
                            color: pc.foregroundC,
                          )),
                      Text(s.reason,
                          style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _insightStat(String label, String value, PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
        const SizedBox(height: 2),
        Text(value, style: PfTypography.bodyMd.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _medalIcon(double score) {
    if (score >= 0.8) {
      return const Icon(Icons.emoji_events, size: 20, color: Color(0xFFF59E0B));
    } else if (score >= 0.5) {
      return const Icon(Icons.emoji_events, size: 20, color: Color(0xFF9CA3AF));
    }
    return const Icon(Icons.emoji_events, size: 20, color: Color(0xFF92400E));
  }

  Widget _buildInsightSkeleton(ThemeData theme, PfColors pc) {
    return PfCard(
      variant: 'default',
      padding: const EdgeInsets.all(PfSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 18, height: 18,
                decoration: BoxDecoration(
                  color: theme.disabledColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Container(width: 160, height: 16,
                decoration: BoxDecoration(
                  color: theme.disabledColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            _skeletonBlock(theme, 70, 14),
            const SizedBox(width: 16),
            _skeletonBlock(theme, 80, 14),
            const SizedBox(width: 16),
            _skeletonBlock(theme, 60, 14),
          ]),
          const SizedBox(height: 12),
          _skeletonBlock(theme, double.infinity, 36),
        ],
      ),
    );
  }

  Widget _skeletonBlock(ThemeData theme, double width, double height) {
    return Container(
      width: width, height: height,
      decoration: BoxDecoration(
        color: theme.disabledColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  // ── Step 1: Strategy ──────────────────────────────────────────────
  Widget _buildStepStrategy(ThemeData theme, PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PhosphorIcon(_kStepIcons[1], size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Выберите стратегию', style: PfTypography.titleLg.copyWith(color: pc.foregroundC)),
            const Spacer(),
            _helpIcon('Стратегия', 'Алгоритм анализа стакана заявок. Каждая стратегия ищет свои паттерны:\n\n• Imbalance Scalping — ловит дисбаланс Bid/Ask\n• Spread Capture — торгует расширение/сужение спреда\n• Order Flow Momentum — реагирует на агрессивные market orders\n• ЕРШ Scalping — сверхчувствительный скальпинг, ловит даже микро-дисбалансы'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Алгоритм для анализа Order Book и принятия решений',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
        // ── Панель пресетов ──
        _buildPresetBar(theme, pc),
        const SizedBox(height: 24),
        // ── Insight карточка с рекомендацией ──
        if (_loadingInsight)
          _buildInsightSkeleton(theme, pc)
        else if (_pairInsight != null) ...[
          _buildInsightCard(_pairInsight!, theme, pc),
          const SizedBox(height: 24),
        ],
        ..._kObStrategies.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildStrategyCard(s, theme, pc),
        )),
        // Если есть параметры у выбранной стратегии
        if (_selectedStrategy != null && _selectedStrategy!.params.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Параметры стратегии', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
          const SizedBox(height: 12),
          ..._selectedStrategy!.params.map((param) =>
            _buildParamSlider(param, theme, pc)),
        ],
      ],
    );
  }

  Widget _buildStrategyCard(_ObStrategyOption s, ThemeData theme, PfColors pc) {
    final selected = _selectedStrategy?.name == s.name;
    return PfCard(
      variant: selected ? 'trading' : 'default',
              onTap: s.enabled ? () {
                _strategyParams.clear();
                for (final p in s.params) {
                  _strategyParams[p.key] = p.defaultValue;
                }
                setState(() => _selectedStrategy = s);
              } : null,
      padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                      : s.enabled
                          ? pc.mutedC
                          : pc.mutedC.withValues(alpha: 0.5),
                  borderRadius: PfRadius.borderRadiusMd,
                ),
                child: Center(
                  child: PhosphorIcon(
                    selected
                        ? PhosphorIconsFill.checkCircle
                        : s.enabled
                            ? PhosphorIconsFill.chartLineUp
                            : PhosphorIconsFill.lock,
                    size: 20,
                    color: selected
                        ? theme.colorScheme.primary
                        : s.enabled
                            ? pc.mutedForegroundC
                            : pc.mutedC,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.label,
                      style: PfTypography.titleMd.copyWith(
                        color: s.enabled ? pc.foregroundC : pc.mutedForegroundC,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.description,
                      style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
                    ),
                  ],
                ),
              ),
              if (!s.enabled)
                PfBadge(variant: 'default', label: 'Скоро'),
            ],
          ),
        ],
      ),
    );
  }

  final Map<String, String> _paramHelpTexts = {
    'imbalance_threshold': 'Порог дисбаланса Bid/Ask. 0.65 = 65% — если одна сторона стакана на 65% тяжелее другой, срабатывает сигнал.',
    'surge_pct': 'Всплеск объёма в % от среднего. Срабатывает, когда объём резко превышает норму.',
    'min_spread_pct': 'Минимальный спред для входа в сделку. Узкий спред = меньше проскальзывание.',
    'spread_entry_threshold': 'Спред расширился до этого порога → вход. Больше значение = реже входы.',
    'spread_exit_threshold': 'Спред сузился до этого порога → выход. Меньше значение = дольше в позиции.',
    'flow_threshold_volume': 'Объём market order (в USDT) для засчитывания сигнала. 10000 = \$10,000.',
    'min_flow_signals': 'Минимальное количество рыночных заявок подряд для подтверждения тренда.',
    'flow_exit_seconds': 'Выход из позиции через N секунд после входа (таймер).',
    'ers_min_imbalance': 'Порог дисбаланса Bid/Ask для входа. 0.52 = 52% — срабатывает даже при слабом доминировании одной стороны. Чем ниже, тем чувствительнее.',
    'ers_min_profit_pct': 'Минимальный профит для выхода в %. 0.01% = ~1 тик на большинстве пар. Выход сразу при движении в +.',
    'ers_max_hold_seconds': 'Максимальное время удержания позиции в секундах. Если за это время нет ни профита, ни реверсии — аварийный выход.',
  };

  Widget _buildParamSlider(_ObStrategyParam param, ThemeData theme, PfColors pc) {
    final val = _strategyParams[param.key] ?? param.defaultValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: PfSpacing.md),
      child: PfCard(
        padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(param.label, style: PfTypography.bodyMd.copyWith(color: pc.foregroundC)),
                    _helpIcon(param.label, _paramHelpTexts[param.key] ?? 'Параметр стратегии. Рекомендуемые значения отмечены в описании.'),
                  ],
                ),
                Text(
                  '${val.toStringAsFixed(val < 1 ? 2 : 0)}${param.unit}',
                  style: PfTypography.titleMd.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            _buildCustomSlider(
              value: val,
              min: param.min,
              max: param.max,
              divisions: param.divisions,
              label: '${val.toStringAsFixed(val < 1 ? 2 : 0)}${param.unit}',
              theme: theme, pc: pc,
              onChange: (v) { _onAnyParamChanged(); setState(() => _strategyParams[param.key] = v); },
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: Balance ───────────────────────────────────────────────
  Widget _buildStepBalance(ThemeData theme, PfColors pc) {
    const presets = [10, 25, 50, 100, 500, 1000, 5000, 10000];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            Row(
              children: [
                PhosphorIcon(_kStepIcons[2], size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Баланс и лимиты', style: PfTypography.titleLg.copyWith(color: pc.foregroundC)),
                const Spacer(),
                _defaultsButton(theme),
                _helpIcon('Баланс', 'Виртуальный баланс для симуляции торговли. Средства не настоящие — вы не рискуете реальным капиталом. Можно изменить в любой момент до запуска.'),
              ],
            ),
        const SizedBox(height: 8),
        Text(
          'Виртуальный баланс для симуляции торговли',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
        _buildStepTip(2, pc),
        // Подсказка о минимальном балансе для выбранной стратегии
        if (_selectedStrategy != null)
          _buildMinBalanceHint(theme, pc),
        const SizedBox(height: 16),
        // Баланс — крупная цифра
        Center(
          child: Text(
            '\$${_balance.toStringAsFixed(0)}',
            style: PfTypography.numberDisplay.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildCustomSlider(
          value: _balance,
          min: 10,
          max: 10000,
          divisions: 99,
          label: '\$${_balance.toStringAsFixed(0)}',
          theme: theme, pc: pc,
          onChange: (v) { _onAnyParamChanged(); setState(() => _balance = v); },
        ),
        const SizedBox(height: 12),
        // Быстрые пресеты
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((v) {
            final isActive = _balance == v;
            return ChoiceChip(
              label: Text('\$${v.toStringAsFixed(0)}'),
              selected: isActive,
              selectedColor: theme.colorScheme.primary,
              onSelected: (_) { _onAnyParamChanged(); setState(() => _balance = v.toDouble()); },
              labelStyle: TextStyle(
                color: isActive ? theme.colorScheme.onPrimary : pc.foregroundC,
              ),
              side: BorderSide(
                color: isActive ? theme.colorScheme.primary : pc.borderC,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: PfRadius.borderRadiusMd,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        // Макс. открытых сделок
        PfCard(
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
          child: Row(
            children: [
              PhosphorIcon(PhosphorIconsFill.arrowsLeftRight, size: 18, color: pc.mutedForegroundC),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Макс. открытых сделок', style: PfTypography.bodyMd.copyWith(color: pc.foregroundC)),
                    const SizedBox(height: 2),
                    Text('Одновременное количество активных позиций', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _maxOpenTrades,
                underline: const SizedBox(),
                dropdownColor: pc.cardC,
                style: PfTypography.titleMd.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                items: [1, 2, 3, 5].map((v) => DropdownMenuItem(
                  value: v,
                  child: Text('$v', style: PfTypography.titleMd.copyWith(
                    color: pc.foregroundC,
                    fontWeight: FontWeight.w600,
                  )),
                )).toList(),
                onChanged: (v) { _onAnyParamChanged(); setState(() => _maxOpenTrades = v!); },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 3: Risk ──────────────────────────────────────────────────
  Widget _buildStepRisk(ThemeData theme, PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PhosphorIcon(_kStepIcons[3], size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Управление рисками', style: PfTypography.titleLg.copyWith(color: pc.foregroundC)),
            const Spacer(),
            _defaultsButton(theme),
            _helpIcon('Риски', 'Настройки защиты капитала: стоп-лосс, трейлинг стоп и максимальное время удержания позиции. Эти параметры ограничивают потери.'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Защита капитала и контроль потерь',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
        _buildStepTip(3, pc),
        _riskCard(
          title: 'Stop Loss',
          subtitle: 'Автоматический выход при падении цены',
          value: '${_stoploss.toStringAsFixed(1)}%',
          valueColor: _stoploss < -2.0 ? PfColors.destructive : pc.foregroundC,
          helpText: 'Автоматический выход из позиции при падении цены на N% от цены входа. Защищает от крупных убытков.',
          slider: _riskSlider(
            value: _stoploss, min: -5.0, max: 0.0, divisions: 50,
            onChange: (v) { _onAnyParamChanged(); setState(() => _stoploss = v); },
            theme: theme, pc: pc,
          ),
          theme: theme, pc: pc,
        ),
        const SizedBox(height: 8),
        _riskCard(
          title: 'Trailing Stop',
          subtitle: 'Динамический стоп, следующий за ценой',
          value: '${_trailingStop.toStringAsFixed(1)}%',
          valueColor: pc.foregroundC,
          helpText: 'Стоп-лосс, который двигается за ценой. Если цена растёт, стоп подтягивается. Если цена падает — стоп остаётся на месте.',
          slider: _riskSlider(
            value: _trailingStop, min: 0.0, max: 2.0, divisions: 40,
            onChange: (v) { _onAnyParamChanged(); setState(() => _trailingStop = v); },
            theme: theme, pc: pc,
          ),
          theme: theme, pc: pc,
        ),
        const SizedBox(height: 8),
        _riskCard(
          title: 'Trailing Offset',
          subtitle: 'Отступ от максимума для активации trailing',
          value: '${_trailingOffset.toStringAsFixed(1)}%',
          valueColor: pc.foregroundC,
          helpText: 'Отступ от максимума цены, при котором активируется трейлинг-стоп. Меньше значение = раньше начнёт двигаться.',
          slider: _riskSlider(
            value: _trailingOffset, min: 0.0, max: 2.0, divisions: 40,
            onChange: (v) { _onAnyParamChanged(); setState(() => _trailingOffset = v); },
            theme: theme, pc: pc,
          ),
          theme: theme, pc: pc,
        ),
        const SizedBox(height: 8),
        _riskCard(
          title: 'Max Hold',
          subtitle: 'Максимальное время удержания позиции',
          value: '${_maxHoldSeconds}s',
          valueColor: pc.foregroundC,
          helpText: 'Максимальное время удержания позиции в секундах. После истечения времени позиция закрывается принудительно.',
          slider: _riskSlider(
            value: _maxHoldSeconds.toDouble(), min: 10, max: 300, divisions: 29,
            onChange: (v) { _onAnyParamChanged(); setState(() => _maxHoldSeconds = v.round()); },
            theme: theme, pc: pc,
          ),
          theme: theme, pc: pc,
        ),
      ],
    );
  }

  Widget _riskCard({
    required String title,
    required String subtitle,
    required String value,
    required Color valueColor,
    required Widget slider,
    required ThemeData theme,
    required PfColors pc,
    String? helpText,
  }) {
    return PfCard(
      padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
                      if (helpText != null) _helpIcon(title, helpText),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
                ],
              ),
              Text(
                value,
                style: PfTypography.number.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          slider,
        ],
      ),
    );
  }

  Widget _riskSlider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChange,
    required ThemeData theme,
    required PfColors pc,
  }) {
    return _buildCustomSlider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      theme: theme, pc: pc,
      onChange: onChange,
    );
  }

  // ── Step 4: Precision ─────────────────────────────────────────────
  Widget _buildStepPrecision(ThemeData theme, PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PhosphorIcon(_kStepIcons[4], size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Точность сигналов', style: PfTypography.titleLg.copyWith(color: pc.foregroundC)),
            const Spacer(),
            _defaultsButton(theme),
            _helpIcon('Точность', 'Настройки подтверждения входов: количество тиков для фильтрации ложных сигналов и максимальный спред для избегания проскальзывания.'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Настройки подтверждения входов и фильтрации шума',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
        _buildStepTip(4, pc),
        PfCard(
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Confirmation Ticks', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
                          _helpIcon('Confirmation Ticks', 'Количество последовательных тиков для подтверждения сигнала входа. Больше тиков = меньше ложных срабатываний, но выше задержка.'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('Количество тиков для подтверждения сигнала', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: PfRadius.borderRadiusMd,
                    ),
                    child: Text(
                      '$_confirmationTicks',
                      style: PfTypography.titleMd.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildCustomSlider(
                value: _confirmationTicks.toDouble(),
                min: 1, max: 10, divisions: 9,
                label: '$_confirmationTicks тиков',
                theme: theme, pc: pc,
                onChange: (v) { _onAnyParamChanged(); setState(() => _confirmationTicks = v.round()); },
              ),
              const SizedBox(height: 16),
              // Текстовая подсказка
              Row(
                children: [
                  PhosphorIcon(PhosphorIconsFill.info, size: 14, color: pc.mutedForegroundC),
                  const SizedBox(width: 6),
                  Text(
                    'Больше тиков = меньше ложных входов, но больше задержка',
                    style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PfCard(
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Max Spread', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
                          _helpIcon('Max Spread', 'Максимальный допустимый спред для входа. Если спред шире — вход не происходит. Защищает от проскальзывания на низколиквидных парах.'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('Максимальный допустимый спред', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: PfRadius.borderRadiusMd,
                    ),
                    child: Text(
                      '${(_maxSpread * 100).toStringAsFixed(1)}%',
                      style: PfTypography.titleMd.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildCustomSlider(
                value: _maxSpread,
                min: 0.01, max: 0.5, divisions: 49,
                label: '${(_maxSpread * 100).toStringAsFixed(1)}%',
                theme: theme, pc: pc,
                onChange: (v) { _onAnyParamChanged(); setState(() => _maxSpread = v); },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 5: Protections ───────────────────────────────────────────
  Widget _buildStepProtections(ThemeData theme, PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PhosphorIcon(_kStepIcons[5], size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Защиты', style: PfTypography.titleLg.copyWith(color: pc.foregroundC)),
            const Spacer(),
            _defaultsButton(theme),
            _helpIcon('Защиты', 'Дополнительные механизмы безопасности: пауза между сделками (cooldown) и автостоп по времени для автоматической остановки стратегии.'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Дополнительные механизмы безопасности',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
        _buildStepTip(5, pc),
        // Cooldown
        PfCard(
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: PfColors.warning.withValues(alpha: 0.12),
                      borderRadius: PfRadius.borderRadiusMd,
                    ),
                    child: Center(
                      child: PhosphorIcon(
                        PhosphorIconsFill.clockCounterClockwise,
                        size: 18,
                        color: PfColors.warning,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Cooldown', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
                            _helpIcon('Cooldown', 'Пауза между сделками после выхода. Предотвращает повторный вход сразу после закрытия позиции, снижая риск флипов.'),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('Пауза между сделками после выхода', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildCustomSlider(
                      value: _cooldownSeconds.toDouble(),
                      min: 10, max: 600, divisions: 59,
                      label: '${_cooldownSeconds}s',
                      theme: theme, pc: pc,
                      onChange: (v) { _onAnyParamChanged(); setState(() => _cooldownSeconds = v.round()); },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: PfColors.warning.withValues(alpha: 0.12),
                      borderRadius: PfRadius.borderRadiusMd,
                    ),
                    child: Text(
                      '${_cooldownSeconds}s',
                      style: PfTypography.titleMd.copyWith(
                        color: PfColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Auto-stop
        PfCard(
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _autoStopHours > 0
                          ? PfColors.destructive.withValues(alpha: 0.12)
                          : pc.mutedC,
                      borderRadius: PfRadius.borderRadiusMd,
                    ),
                    child: Center(
                      child: PhosphorIcon(
                        PhosphorIconsFill.timer,
                        size: 18,
                        color: _autoStopHours > 0
                            ? PfColors.destructive
                            : pc.mutedForegroundC,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Автостоп по времени', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
                            _helpIcon('Автостоп', 'Автоматическая остановка стратегии через N часов. Полезно чтобы стратегия не работала бесконечно. 0 = отключено.'),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('Автоматическая остановка стратегии через N часов', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildCustomSlider(
                      value: _autoStopHours.toDouble(),
                      min: 0, max: 24, divisions: 24,
                      label: _autoStopHours > 0 ? '$_autoStopHours ч.' : 'Выкл',
                      destructive: true,
                      theme: theme, pc: pc,
                      onChange: (v) { _onAnyParamChanged(); setState(() => _autoStopHours = v.round()); },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _autoStopHours > 0
                          ? PfColors.destructive.withValues(alpha: 0.12)
                          : pc.mutedC,
                      borderRadius: PfRadius.borderRadiusMd,
                    ),
                    child: Text(
                      _autoStopHours > 0 ? '${_autoStopHours}ч' : 'Выкл',
                      style: PfTypography.titleMd.copyWith(
                        color: _autoStopHours > 0 ? PfColors.destructive : pc.mutedForegroundC,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (_autoStopHours > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      PhosphorIcon(PhosphorIconsFill.info, size: 12, color: PfColors.destructive.withValues(alpha: 0.7)),
                      const SizedBox(width: 6),
                      Text(
                        'Стратегия остановится через $_autoStopHours ч.',
                        style: PfTypography.bodySm.copyWith(color: PfColors.destructive.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Доп. защиты (в будущем)
        PfCard(
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: pc.mutedC,
                  borderRadius: PfRadius.borderRadiusMd,
                ),
                child: Center(
                  child: PhosphorIcon(PhosphorIconsFill.lock, size: 18, color: pc.mutedForegroundC),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Low Profit Guard', style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC)),
                    const SizedBox(height: 2),
                    Text('Автостоп при низкой доходности (скоро)', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC.withValues(alpha: 0.6))),
                  ],
                ),
              ),
              PfBadge(variant: 'default', label: 'Скоро'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        PfCard(
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: pc.mutedC,
                  borderRadius: PfRadius.borderRadiusMd,
                ),
                child: Center(
                  child: PhosphorIcon(PhosphorIconsFill.trendDown, size: 18, color: pc.mutedForegroundC),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Max Drawdown', style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC)),
                    const SizedBox(height: 2),
                    Text('Автостоп при превышении просадки (скоро)', style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC.withValues(alpha: 0.6))),
                  ],
                ),
              ),
              PfBadge(variant: 'default', label: 'Скоро'),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 6: Summary ───────────────────────────────────────────────
  Widget _buildStepSummary(ThemeData theme, PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PhosphorIcon(_kStepIcons[6], size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Сводка настроек', style: PfTypography.titleLg.copyWith(color: pc.foregroundC)),
            const Spacer(),
            _helpIcon('Сводка', 'Проверьте все настройки перед запуском. Кнопка «Стандартные» на предыдущих шагах сбросит параметры к рекомендованным для выбранной стратегии.'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Проверьте параметры перед запуском',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
        // Основная сводка
        PfCard(
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
          child: Column(
            children: [
              _summaryRow(pc, 'Пара', _selectedPairSymbol, theme.colorScheme.primary),
              const PfDivider(indent: 0),
              _summaryRow(pc, 'Стратегия', _selectedStrategy?.label ?? '', theme.colorScheme.primary),
              const PfDivider(indent: 0),
              _summaryRow(pc, 'Баланс', '\$${_balance.toStringAsFixed(0)}', theme.colorScheme.primary),
              const PfDivider(indent: 0),
              _summaryRow(pc, 'Stop Loss', '${_stoploss.toStringAsFixed(1)}%', _stoploss < -2.0 ? PfColors.destructive : pc.foregroundC),
              const PfDivider(indent: 0),
              _summaryRow(pc, 'Trailing Stop', '${_trailingStop.toStringAsFixed(1)}% / offset ${_trailingOffset.toStringAsFixed(1)}%', pc.foregroundC),
              const PfDivider(indent: 0),
              _summaryRow(pc, 'Max Hold', '${_maxHoldSeconds}s', pc.foregroundC),
              const PfDivider(indent: 0),
              _summaryRow(pc, 'Cooldown', '${_cooldownSeconds}s', PfColors.warning),
              const PfDivider(indent: 0),
              _summaryRow(pc, 'Автостоп', _autoStopHours > 0 ? '$_autoStopHours ч.' : 'Выкл', _autoStopHours > 0 ? PfColors.destructive : pc.mutedForegroundC),
              const PfDivider(indent: 0),
              _summaryRow(pc, 'Точность', '$_confirmationTicks тиков / spread ${(_maxSpread * 100).toStringAsFixed(1)}%', pc.foregroundC),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Предупреждение о режиме
        Container(
          padding: const EdgeInsets.all(PfSpacing.md),
          decoration: BoxDecoration(
            color: PfColors.warning.withValues(alpha: 0.08),
            borderRadius: PfRadius.borderRadiusLg,
            border: Border.all(color: PfColors.warning.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhosphorIcon(
                PhosphorIconsFill.warning,
                size: 20,
                color: PfColors.warning,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Режим Virtual',
                      style: PfTypography.titleMd.copyWith(
                        color: PfColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Работает только в virtual режиме — реальные данные Binance через WebSocket, виртуальный баланс. Без риска для капитала.',
                      style: PfTypography.bodyMd.copyWith(color: pc.foregroundC),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ── Live-статус запуска ──
        if (_runStarted)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: PfCard(
              variant: 'trading',
              padding: const EdgeInsets.all(PfSpacing.lg),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _runStatusText.contains('✅')
                              ? PfColors.success
                              : _runStatusText.contains('❌')
                                  ? PfColors.destructive
                                  : PfColors.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _runStatusText,
                        style: PfTypography.titleMd.copyWith(
                          color: _runStatusText.contains('✅')
                              ? PfColors.success
                              : _runStatusText.contains('❌')
                                  ? PfColors.destructive
                                  : PfColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!_runStatusText.contains('❌') && !_runStatusText.contains('⏹️'))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Стратегия работает в фоне. Вы можете вернуться на Trading Page и следить за статусом.',
                        style: PfTypography.bodySm.copyWith(
                          color: pc.mutedForegroundC,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PfButton(
                        variant: 'secondary',
                        size: 'md',
                        label: 'Подробнее',
                        onPressed: () => context.go('/trading/ob-run/$_lastRunId'),
                      ),
                      const SizedBox(width: 12),
                      PfButton(
                        variant: 'primary',
                        size: 'md',
                        label: 'На Trading Page',
                        onPressed: () => context.go('/trading'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _summaryRow(PfColors pc, String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PfSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(label, style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC)),
            ],
          ),
          Text(
            value,
            style: PfTypography.bodyMd.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Navigation ────────────────────────────────────────────────────
  Widget _buildNavigation(ThemeData theme, PfColors pc) {
    // Когда запуск выполнен — скрываем навигацию
    if (_runStarted) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(PfSpacing.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: pc.borderC)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: PfButton(
                  variant: 'outline',
                  size: 'lg',
                  label: 'Назад',
                  onPressed: () {
                    _previousStep = _currentStep;
                    setState(() => _currentStep--);
                    _slideCtrl.forward(from: 0);
                  },
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 12),
            Expanded(
              child: PfButton(
                variant: 'primary',
                size: 'lg',
                label: _currentStep < 6 ? 'Далее' : '🚀 Запустить',
                onPressed: _isLoading ? null : () {
                  if (_currentStep < 6) {
                    _previousStep = _currentStep;
                    setState(() => _currentStep++);
                    _slideCtrl.forward(from: 0);
                    // Загрузить insight при переходе на шаг стратегии
                    if (_currentStep == 1 && _selectedPairSymbol.isNotEmpty) {
                      _fetchPairInsight(_selectedPairSymbol);
                    }
                  } else {
                    _startEngine();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startEngine() async {
    setState(() => _isLoading = true);
    try {
      final request = <String, dynamic>{
        'pair': _selectedPairSymbol,
        'strategy': _selectedStrategy?.name ?? 'imbalance_scalping',
        'initial_balance': _balance,
        'max_open_trades': _maxOpenTrades,
        'stoploss': _stoploss,
        'trailing_stop': _trailingStop,
        'trailing_offset': _trailingOffset,
        'max_hold_seconds': _maxHoldSeconds,
        'confirmation_ticks': _confirmationTicks,
        'max_spread': _maxSpread,
        'cooldown_seconds': _cooldownSeconds,
        'auto_stop_hours': _autoStopHours,
        'source_exchange': _sourceExchange,
        'trade_exchange': _tradeExchange,
      };

      // Add strategy-specific params
      for (final entry in _strategyParams.entries) {
        request[entry.key] = entry.value;
      }
      final response = await _repository.startOrderBookRun(request);
      if (mounted) {
        setState(() => _isLoading = false);
        final runId = response['id'] as int?;
        if (runId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Expanded(child: Text('✅ Запуск успешно создан!')),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16),
              duration: const Duration(seconds: 3),
            ),
          );
          _startPolling(runId);
        } else {
          showErrorSnackbar(context, '❌ Запуск не создан: API вернул пустой ответ');
        }
      }
    } catch (e) {
      debugPrint('[OB START ERROR] $e');
      if (mounted) {
        setState(() => _isLoading = false);
        String msg;
        if (e is DioException) {
          final statusCode = e.response?.statusCode;
          final detail = e.response?.data is Map
              ? (e.response?.data as Map)['detail']
              : null;
          if (statusCode == 401 || statusCode == 403) {
            msg = '🔐 Ошибка авторизации. Попробуйте перезайти в приложение.';
          } else if (statusCode == 429) {
            msg = '⏳ Достигнут лимит запусков. Остановите активный запуск.';
          } else if (detail != null) {
            msg = '❌ $detail';
          } else if (statusCode != null) {
            msg = '❌ Ошибка HTTP $statusCode. Сервер не отвечает.';
          } else {
            msg = '❌ Нет соединения с сервером. Проверьте подключение.';
          }
        } else if (e is FormatException) {
          msg = '❌ Ошибка ответа сервера. Попробуйте снова.';
        } else {
          msg = '❌ Не удалось запустить стратегию: $e';
        }
        showErrorSnackbar(context, msg);
      }
    }
  }

  // ── Live data helpers ──────────────────────────────────────────────

  String _obFormatPrice(double price) {
    if (price >= 1000) return '\$${(price / 1000).toStringAsFixed(1)}K';
    if (price >= 1) return '\$${price.toStringAsFixed(2)}';
    if (price >= 0.01) return '\$${price.toStringAsFixed(4)}';
    return '\$${price.toStringAsFixed(6)}';
  }

  String _obFormatChange(double change) {
    final sign = change >= 0 ? '+' : '';
    return '$sign${change.toStringAsFixed(2)}%';
  }

  String _obFormatVolume(double volume) {
    if (volume >= 1_000_000_000) {
      return '${(volume / 1_000_000_000).toStringAsFixed(1)}B';
    }
    if (volume >= 1_000_000) {
      return '${(volume / 1_000_000).toStringAsFixed(1)}M';
    }
    if (volume >= 1_000) {
      return '${(volume / 1_000).toStringAsFixed(1)}K';
    }
    return volume.toStringAsFixed(0);
  }

  Widget _obSkeletonColumn(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 14,
              decoration: BoxDecoration(
                color: theme.disabledColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 45,
                  height: 11,
                  decoration: BoxDecoration(
                    color: theme.disabledColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 35,
                  height: 11,
                  decoration: BoxDecoration(
                    color: theme.disabledColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(width: 12),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  Widget _buildExchangeDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
    required PfColors pc,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: pc.cardC,
        borderRadius: PfRadius.borderRadiusMd,
        border: Border.all(color: pc.borderC),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: pc.cardC,
          style: PfTypography.bodySm.copyWith(
            color: pc.foregroundC,
            fontWeight: FontWeight.w500,
          ),
          items: items.map((e) => DropdownMenuItem(
            value: e,
            child: Text(e[0].toUpperCase() + e.substring(1),
              style: PfTypography.bodySm.copyWith(
                color: pc.foregroundC,
                fontWeight: FontWeight.w500,
              ),
            ),
          )).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
