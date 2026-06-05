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
    description: 'Торговля по спреду / Market Making Lite (скоро)',
    enabled: false,
  ),
  _ObStrategyOption(
    name: 'order_flow_momentum',
    label: 'Order Flow Momentum',
    description: 'Агрессивные market orders как сигнал (скоро)',
    enabled: false,
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

class OrderBookWizardPage extends StatefulWidget {
  final TradingRepository repository;

  const OrderBookWizardPage({super.key, required this.repository});

  @override
  State<OrderBookWizardPage> createState() => _OrderBookWizardPageState();
}

class _OrderBookWizardPageState extends State<OrderBookWizardPage> {
  int _currentStep = 0;
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

  // Step 1: Strategy
  _ObStrategyOption? _selectedStrategy;

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

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedStrategy = _kObStrategies.firstWhere((s) => s.enabled);
    _loadPairs();
    _pairScrollController.addListener(() {
      if (_pairScrollController.position.pixels >=
          _pairScrollController.position.maxScrollExtent - 200) {
        if (_hasMorePairs && !_loadingPairs) {
          setState(() => _pairPage++);
          _loadPairs();
        }
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
    if (index <= _currentStep + 1) {
      setState(() => _currentStep = index);
    }
  }

  // ── Загрузка пар ──────────────────────────────────────────────────

  Future<void> _loadPairs({bool refresh = false}) async {
    if (_loadingPairs) return;
    if (refresh) {
      _loadedPairs.clear();
      _pairPage = 1;
      _hasMorePairs = true;
    }
    setState(() => _loadingPairs = true);
    try {
      final result = await _repository.getPairs(
        search: _searchPairController.text.isNotEmpty
            ? _searchPairController.text
            : null,
        page: _pairPage,
        pageSize: 50,
      );
      if (mounted) {
        setState(() {
          _loadedPairs.addAll(result.items);
          _hasMorePairs = _loadedPairs.length < result.total;
          _loadingPairs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPairs = false);
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

  // ── Step Content Router ────────────────────────────────────────────
  Widget _buildStepContent(ThemeData theme, PfColors pc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(PfSpacing.lg),
      child: _buildStepWidget(theme, pc),
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

  // ── Step 0: Pair ──────────────────────────────────────────────────
  Widget _buildStepPair(ThemeData theme, PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PhosphorIcon(_kStepIcons[0], size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Выберите пару', style: PfTypography.titleLg.copyWith(color: pc.foregroundC)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Поиск и выбор торговой пары для Order Book стратегии',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 4),
        if (_loadingPairs && _loadedPairs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        const SizedBox(height: 8),
        // Pair list
        ..._loadedPairs.map((pair) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: PfCard(
            variant: _selectedPairSymbol == pair.symbol ? 'trading' : 'default',
            onTap: () => setState(() => _selectedPairSymbol = pair.symbol),
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
                  child: Center(
                    child: Text(
                      pair.base.isNotEmpty ? pair.base[0] : '?',
                      style: PfTypography.titleMd.copyWith(
                        color: _selectedPairSymbol == pair.symbol
                            ? theme.colorScheme.primary
                            : pc.mutedForegroundC,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
            ),
          ),
        )),
        // Load more trigger
        if (_hasMorePairs && _loadingPairs)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (_hasMorePairs && !_loadingPairs)
          GestureDetector(
            onTap: () {
              setState(() => _pairPage++);
              _loadPairs();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Загрузить ещё... (${_loadedPairs.length} показано)',
                  style: PfTypography.bodySm.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        if (!_hasMorePairs && _loadedPairs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                'Все пары загружены (${_loadedPairs.length})',
                style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
              ),
            ),
          ),
      ],
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
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Алгоритм для анализа Order Book и принятия решений',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
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
      onTap: s.enabled ? () => setState(() => _selectedStrategy = s) : null,
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

  Widget _buildParamSlider(_ObStrategyParam param, ThemeData theme, PfColors pc) {
    // Хардкодим значения параметров для MVP
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
                Text(param.label, style: PfTypography.bodyMd.copyWith(color: pc.foregroundC)),
                Text(
                  '${param.defaultValue.toStringAsFixed(param.defaultValue < 1 ? 2 : 0)}${param.unit}',
                  style: PfTypography.titleMd.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Slider(
              value: param.defaultValue,
              min: param.min,
              max: param.max,
              divisions: param.divisions,
              activeColor: theme.colorScheme.primary,
              inactiveColor: pc.mutedC,
              onChanged: (_) {}, // MVP — readonly пока
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: Balance ───────────────────────────────────────────────
  Widget _buildStepBalance(ThemeData theme, PfColors pc) {
    const presets = [100, 500, 1000, 5000, 10000];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            Row(
              children: [
                PhosphorIcon(_kStepIcons[2], size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Баланс и лимиты', style: PfTypography.titleLg.copyWith(color: pc.foregroundC)),
                _helpIcon('Баланс', 'Виртуальный баланс для симуляции торговли. Средства не настоящие — вы не рискуете реальным капиталом. Можно изменить в любой момент до запуска.'),
              ],
            ),
        const SizedBox(height: 8),
        Text(
          'Виртуальный баланс для симуляции торговли',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
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
        Slider(
          value: _balance,
          min: 100,
          max: 10000,
          divisions: 99,
          activeColor: theme.colorScheme.primary,
          inactiveColor: pc.mutedC,
          onChanged: (v) => setState(() => _balance = v),
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
              onSelected: (_) => setState(() => _balance = v.toDouble()),
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
                onChanged: (v) => setState(() => _maxOpenTrades = v!),
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
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Защита капитала и контроль потерь',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
        _riskCard(
          title: 'Stop Loss',
          subtitle: 'Автоматический выход при падении цены',
          value: '${_stoploss.toStringAsFixed(1)}%',
          valueColor: _stoploss < -2.0 ? PfColors.destructive : pc.foregroundC,
          slider: _riskSlider(
            value: _stoploss, min: -5.0, max: 0.0, divisions: 50,
            onChange: (v) => setState(() => _stoploss = v),
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
          slider: _riskSlider(
            value: _trailingStop, min: 0.0, max: 2.0, divisions: 40,
            onChange: (v) => setState(() => _trailingStop = v),
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
          slider: _riskSlider(
            value: _trailingOffset, min: 0.0, max: 2.0, divisions: 40,
            onChange: (v) => setState(() => _trailingOffset = v),
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
          slider: _riskSlider(
            value: _maxHoldSeconds.toDouble(), min: 10, max: 300, divisions: 29,
            onChange: (v) => setState(() => _maxHoldSeconds = v.round()),
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
                  Text(title, style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
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
    return Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      activeColor: theme.colorScheme.primary,
      inactiveColor: pc.mutedC,
      onChanged: onChange,
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
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Настройки подтверждения входов и фильтрации шума',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
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
                      Text('Confirmation Ticks', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
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
              Slider(
                value: _confirmationTicks.toDouble(),
                min: 1, max: 10, divisions: 9,
                activeColor: theme.colorScheme.primary,
                inactiveColor: pc.mutedC,
                onChanged: (v) => setState(() => _confirmationTicks = v.round()),
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
                      Text('Max Spread', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
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
              Slider(
                value: _maxSpread,
                min: 0.01, max: 0.5, divisions: 49,
                activeColor: theme.colorScheme.primary,
                inactiveColor: pc.mutedC,
                onChanged: (v) => setState(() => _maxSpread = v),
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
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Дополнительные механизмы безопасности',
          style: PfTypography.bodyMd.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),
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
                        Text('Cooldown', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
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
                    child: Slider(
                      value: _cooldownSeconds.toDouble(),
                      min: 10, max: 600, divisions: 59,
                      activeColor: theme.colorScheme.primary,
                      inactiveColor: pc.mutedC,
                      onChanged: (v) => setState(() => _cooldownSeconds = v.round()),
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
                  onPressed: () => setState(() => _currentStep--),
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
                    setState(() => _currentStep++);
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
      await _repository.startOrderBookRun({
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
      });
      if (mounted) {
        setState(() => _isLoading = false);
        context.go('/trading');
      }
    } catch (e) {
      debugPrint('[OB START ERROR] $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
