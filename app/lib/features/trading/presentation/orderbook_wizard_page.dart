import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/adaptive_scaffold.dart';
import 'package:app/shared/widgets/pf_button.dart';

/// Параметр стратегии Order Book.
class _ObStrategyParam {
  final String key;
  final String label;
  final double defaultValue;
  final double min;
  final double max;
  final int divisions;

  const _ObStrategyParam({
    required this.key,
    required this.label,
    required this.defaultValue,
    this.min = 0,
    this.max = 100,
    this.divisions = 100,
  });
}

/// Модель стратегии Order Book.
class _ObStrategyOption {
  final String name;
  final String label;
  final String description;
  final Color color;
  final bool enabled;
  final List<_ObStrategyParam> params;

  const _ObStrategyOption({
    required this.name,
    required this.label,
    required this.description,
    this.color = const Color(0xFF5E6AD2),
    this.enabled = true,
    this.params = const [],
  });
}

/// Доступные OB-стратегии.
const _kObStrategies = [
  _ObStrategyOption(
    name: 'imbalance_scalping',
    label: 'Imbalance Scalping',
    description: 'Ловит дисбаланс bid/ask с 3-тик подтверждением',
    params: [
      _ObStrategyParam(
        key: 'imbalance_threshold',
        label: 'Порог дисбаланса',
        defaultValue: 0.65, min: 0.55, max: 0.85, divisions: 30,
      ),
      _ObStrategyParam(
        key: 'surge_pct',
        label: 'Всплеск объёма %',
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

class OrderBookWizardPage extends StatefulWidget {
  const OrderBookWizardPage({super.key});

  @override
  State<OrderBookWizardPage> createState() => _OrderBookWizardPageState();
}

class _OrderBookWizardPageState extends State<OrderBookWizardPage> {
  int _currentStep = 0;

  // Step 0: Pair
  String _selectedPair = 'BTCUSDT';
  final _pairs = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'TONUSDT', 'BNBUSDT'];

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
  }

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);
    return AdaptiveScaffold(
      title: 'Order Book стратегия',
      currentPath: '/trading/orderbook-wizard',
      showBackButton: true,
      body: Column(
        children: [
          // Step indicator
          Padding(
            padding: const EdgeInsets.fromLTRB(PfSpacing.lg, PfSpacing.md, PfSpacing.lg, 0),
            child: Row(
              children: List.generate(7, (i) {
                final isActive = i <= _currentStep;
                return Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isActive
                          ? PfColors.accentAdmin
                          : pc.borderC,
                      borderRadius: PfRadius.borderRadiusPill,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: PfSpacing.lg),
          // Step content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
              child: _buildStepContent(pc),
            ),
          ),
          // Navigation
          _buildNavigation(pc),
        ],
      ),
    );
  }

  Widget _buildStepContent(PfColors pc) {
    switch (_currentStep) {
      case 0: return _buildStepPair(pc);
      case 1: return _buildStepStrategy(pc);
      case 2: return _buildStepBalance(pc);
      case 3: return _buildStepRisk(pc);
      case 4: return _buildStepPrecision(pc);
      case 5: return _buildStepProtections(pc);
      case 6: return _buildStepSummary(pc);
      default: return const SizedBox();
    }
  }

  // ── Step 0: Pair ──────────────────────────────────────────────────
  Widget _buildStepPair(PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Выберите пару', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
        const SizedBox(height: 16),
        ..._pairs.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: _selectedPair == p ? PfColors.accentAdmin.withValues(alpha: 0.08) : pc.cardC,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _selectedPair = p),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _selectedPair == p
                          ? PhosphorIconsFill.checkCircle
                          : PhosphorIconsFill.circle,
                      color: _selectedPair == p ? PfColors.accentAdmin : pc.mutedForegroundC,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(p, style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: pc.foregroundC,
                    )),
                  ],
                ),
              ),
            ),
          ),
        )),
      ],
    );
  }

  // ── Step 1: Strategy ──────────────────────────────────────────────
  Widget _buildStepStrategy(PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Выберите стратегию', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
        const SizedBox(height: 16),
        ..._kObStrategies.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildStrategyCard(s, pc),
        )),
      ],
    );
  }

  Widget _buildStrategyCard(_ObStrategyOption s, PfColors pc) {
    final selected = _selectedStrategy?.name == s.name;
    return Material(
      color: selected ? PfColors.accentAdmin.withValues(alpha: 0.08) : pc.cardC,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: s.enabled ? () => setState(() => _selectedStrategy = s) : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? PfColors.accentAdmin : pc.borderC,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? PhosphorIconsFill.checkCircle
                        : (s.enabled
                            ? PhosphorIconsFill.circle
                            : PhosphorIconsFill.lock),
                    color: selected ? PfColors.accentAdmin : pc.mutedForegroundC,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(s.label, style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: s.enabled ? pc.foregroundC : pc.mutedForegroundC,
                    )),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(s.description, style: TextStyle(
                fontSize: 12,
                color: pc.mutedForegroundC,
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 2: Balance ───────────────────────────────────────────────
  Widget _buildStepBalance(PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Баланс и лимиты', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
        const SizedBox(height: 16),
        Text('Стартовый баланс: \$${_balance.toStringAsFixed(0)}',
            style: TextStyle(color: pc.foregroundC)),
        Slider(
          value: _balance,
          min: 100, max: 10000, divisions: 99,
          onChanged: (v) => setState(() => _balance = v),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Макс. открытых сделок:', style: TextStyle(color: pc.foregroundC)),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _maxOpenTrades,
              dropdownColor: pc.cardC,
              items: [1, 2, 3, 5].map((v) => DropdownMenuItem(
                value: v, child: Text('$v', style: TextStyle(color: pc.foregroundC)),
              )).toList(),
              onChanged: (v) => setState(() => _maxOpenTrades = v!),
            ),
          ],
        ),
      ],
    );
  }

  // ── Step 3: Risk ──────────────────────────────────────────────────
  Widget _buildStepRisk(PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Риски', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
        const SizedBox(height: 16),
        _riskSlider('Stop Loss', '%', _stoploss, -5.0, 0.0, 50, (v) => setState(() => _stoploss = v), pc),
        _riskSlider('Trailing Stop', '%', _trailingStop, 0.0, 2.0, 40, (v) => setState(() => _trailingStop = v), pc),
        _riskSlider('Trailing Offset', '%', _trailingOffset, 0.0, 2.0, 40, (v) => setState(() => _trailingOffset = v), pc),
        _riskSlider('Max Hold', 's', _maxHoldSeconds.toDouble(), 10, 300, 29, (v) => setState(() => _maxHoldSeconds = v.round()), pc),
      ],
    );
  }

  Widget _riskSlider(String label, String unit, double value, double min, double max, int div, ValueChanged<double> onChange, PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: pc.foregroundC)),
            Text('${value.toStringAsFixed(2)}$unit',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: pc.foregroundC)),
          ],
        ),
        Slider(value: value, min: min, max: max, divisions: div, onChanged: onChange),
      ],
    );
  }

  // ── Step 4: Precision ─────────────────────────────────────────────
  Widget _buildStepPrecision(PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Точность', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
        const SizedBox(height: 16),
        Text('Confirmation ticks: $_confirmationTicks',
            style: TextStyle(color: pc.foregroundC)),
        Slider(
          value: _confirmationTicks.toDouble(), min: 1, max: 10, divisions: 9,
          onChanged: (v) => setState(() => _confirmationTicks = v.round()),
        ),
        const SizedBox(height: 16),
        Text('Max spread: ${_maxSpread.toStringAsFixed(3)}%',
            style: TextStyle(color: pc.foregroundC)),
        Slider(
          value: _maxSpread, min: 0.01, max: 0.5, divisions: 49,
          onChanged: (v) => setState(() => _maxSpread = v),
        ),
      ],
    );
  }

  // ── Step 5: Protections ───────────────────────────────────────────
  Widget _buildStepProtections(PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Защиты', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
        const SizedBox(height: 16),
        Text('Cooldown: ${_cooldownSeconds}s',
            style: TextStyle(color: pc.foregroundC)),
        Slider(
          value: _cooldownSeconds.toDouble(), min: 10, max: 600, divisions: 59,
          onChanged: (v) => setState(() => _cooldownSeconds = v.round()),
        ),
      ],
    );
  }

  // ── Step 6: Summary ───────────────────────────────────────────────
  Widget _buildStepSummary(PfColors pc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Сводка', style: PfTypography.titleMd.copyWith(color: pc.foregroundC)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pc.cardC,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: pc.borderC),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Пара', _selectedPair, pc),
              _infoRow('Стратегия', _selectedStrategy?.label ?? '', pc),
              _infoRow('Баланс', '\$${_balance.toStringAsFixed(0)}', pc),
              _infoRow('Stop Loss', '${_stoploss.toStringAsFixed(1)}%', pc),
              _infoRow('Trailing', '${_trailingStop.toStringAsFixed(2)}% / offset ${_trailingOffset.toStringAsFixed(2)}%', pc),
              _infoRow('Max Hold', '${_maxHoldSeconds}s', pc),
              _infoRow('Cooldown', '${_cooldownSeconds}s', pc),
              _infoRow('Точность', '$_confirmationTicks тиков / spread ${_maxSpread.toStringAsFixed(3)}%', pc),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PfColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PfColors.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsFill.warning, color: PfColors.warning, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Работает только в virtual режиме — реальные данные Binance + виртуальный баланс',
                  style: TextStyle(fontSize: 12, color: pc.foregroundC),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value, PfColors pc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: pc.mutedForegroundC)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pc.foregroundC)),
        ],
      ),
    );
  }

  // ── Navigation ────────────────────────────────────────────────────
  Widget _buildNavigation(PfColors pc) {
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
    // TODO: POST /api/v1/orderbook/start с конфигом
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _isLoading = false);
      context.go('/trading');
    }
  }
}
