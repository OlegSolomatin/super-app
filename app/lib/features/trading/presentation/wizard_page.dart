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
import 'package:app/shared/widgets/pf_button.dart';
import 'package:app/core/theme.dart';
import 'package:app/features/trading/data/models/trading_pair.dart';
import 'package:app/features/trading/data/models/strategy_info.dart';
import 'package:app/features/trading/data/models/exchange_info.dart';
import 'package:app/features/trading/data/trading_repository.dart';
import 'package:app/shared/widgets/responsive_layout.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/settings/data/settings_repository.dart';
import 'package:app/features/trading/data/hardcoded_pairs.dart';
import 'package:app/features/trading/data/models/pair_live_data.dart';

enum RunMode { historical, virtual, real }

class TradingWizardPage extends StatefulWidget {
  final TradingRepository repository;

  const TradingWizardPage({super.key, required this.repository});

  @override
  State<TradingWizardPage> createState() => _TradingWizardPageState();
}

class _TradingWizardPageState extends State<TradingWizardPage> {
  int _currentStep = 0;
  bool _loadingStep = false;

  // Step 1
  RunMode? _runMode;

  // Step 2
  final List<TradingPair> _pairs = [];
  List<ExchangeInfo> _exchanges = [];
  TradingPair? _selectedPair;
  ExchangeInfo? _selectedExchange;
  final TextEditingController _searchPairController = TextEditingController();
  final TextEditingController _searchStrategyController =
      TextEditingController();
  int _pairPage = 1;
  bool _hasMorePairs = true;
  bool _loadingPairs = false;
  bool _sortByVolume = false;
  Map<String, PairLiveData> _liveData = {};
  bool _loadingLiveData = false;

  // Step 3
  List<StrategyInfo> _strategies = [];
  StrategyInfo? _selectedStrategy;
  bool _loadingStrategies = false;

  // Step 4
  double _leverage = 1;
  // Hardcoded in strategy: SL=2%, TP=5%

  // Step 5
  double _balance = 1000;

  // Step 6
  double _maxTrade = 100;

  // Step 7
  String? _timeframe;

  // Step 8
  DateTimeRange? _dateRange;
  int? _duration;

  // Notification
  bool _notifyTrades = false;
  String? _notificationBotId;
  List<TelegramBotData> _bots = [];
  bool _loadingBots = false;

  // Trend filter
  bool _trendFilterEnabled = true;
  int _trendFilterPeriod = 200;

  bool get _isPairScanner => _selectedStrategy?.isPairScanner ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ThemeProvider>().setSection(SectionTheme.trading);
      }
    });
    _loadStrategies();
  }

  @override
  void dispose() {
    _searchPairController.dispose();
    _searchStrategyController.dispose();
    super.dispose();
  }

  Future<void> _loadPairs({bool refresh = false}) async {
    if (refresh) {
      _pairPage = 1;
    }
    setState(() => _loadingPairs = true);
    // Локальная фильтрация из hardcoded_pairs.dart — без API-запроса
    final search = _searchPairController.text.trim().toUpperCase();
    var filtered = allTradingPairs.where((p) {
      if (search.isEmpty) return true;
      return p.symbol.contains(search) || p.base.contains(search);
    }).toList();
    if (!mounted) return;
    setState(() {
      _pairs
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
      final liveData = await widget.repository.getPairsLive();
      if (mounted) {
        setState(() {
          _liveData = liveData;
          _loadingLiveData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLiveData = false);
    }
  }

  Future<void> _loadExchanges() async {
    try {
      final result = await widget.repository.getExchanges();
      if (mounted) {
        setState(() => _exchanges = result.items);
      }
    } catch (_) {}
  }

  Future<void> _loadStrategies() async {
    setState(() => _loadingStrategies = true);
    try {
      final result = await widget.repository.getStrategies();
      if (mounted) {
        setState(() {
          _strategies = result.items;
          _loadingStrategies = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStrategies = false);
    }
  }

  Future<void> _loadBots() async {
    if (_loadingBots) return;
    setState(() => _loadingBots = true);
    try {
      final storage = SecureStorage();
      final dioClient = DioClient(storage);
      final repository = SettingsRepository(dioClient.dio);
      final bots = await repository.getBots();
      if (mounted) {
        setState(() {
          _bots = bots;
          _loadingBots = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBots = false);
    }
  }

  void _onStepTapped(int step) {
    if (step <= _currentStep + 1 &&
        (_runMode != null || step == 0) &&
        (_isPairScanner || _selectedPair != null ||
            _selectedExchange != null ||
            _runMode == null ||
            step <= 2) &&
        (_selectedStrategy != null || step <= 3) &&
        (_timeframe != null || step <= 7)) {
      setState(() => _currentStep = step);
    }
  }

  void _nextStep() {
    if (_currentStep < 8) {
      if (_currentStep == 0 && _runMode != null) {
        if (_runMode == RunMode.real) {
          _loadExchanges();
        } else {
          _loadPairs();
          _fetchLiveData();
        }
      }
      if (_currentStep == 1 && _runMode == RunMode.real && _exchanges.isEmpty) {
        _loadExchanges();
      }
      if (_currentStep == 7) {
        _loadBots();
      }
      setState(() => _currentStep++);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0:
        return _runMode != null;
      case 1:
        return _isPairScanner || (_runMode == RunMode.real
            ? _selectedExchange != null
            : _selectedPair != null);
      case 2:
        return _selectedStrategy != null;
      case 3:
        return _leverage > 0;
      case 4:
        return _runMode == RunMode.real || _balance > 0;
      case 5:
        return _maxTrade > 0;
      case 6:
        return _timeframe != null;
      case 7:
        return _runMode == RunMode.historical
            ? _dateRange != null
            : _runMode == RunMode.virtual
                ? _duration != null
                : true;
      case 8:
        return true;
      default:
        return false;
    }
  }

  String _modeApiValue(RunMode mode) {
    return switch (mode) {
      RunMode.historical => 'history',
      RunMode.virtual => 'virtual',
      RunMode.real => 'real',
    };
  }

  Future<void> _submitRun() async {
    setState(() => _loadingStep = true);
    try {
      final config = <String, dynamic>{
        'mode': _modeApiValue(_runMode!),
        'strategy': _selectedStrategy!.name,
        'leverage': _leverage.round(),
        'timeframe': _timeframe,
      };
      if (_runMode != RunMode.real) {
        if (!_isPairScanner) {
          config['pair'] = _selectedPair!.symbol;
        }
        config['virtual_balance'] = _balance;
        config['max_trade_amount'] = _maxTrade;
      } else {
        config['exchange'] = _selectedExchange!.name;
      }
      if (_runMode == RunMode.historical && _dateRange != null) {
        config['period_start'] = _dateRange!.start.toIso8601String();
        config['period_end'] = _dateRange!.end.toIso8601String();
      }
      if (_runMode == RunMode.virtual && _duration != null) {
        config['duration_days'] = _duration;
      }
      if (_notifyTrades && _notificationBotId != null) {
        config['notification_bot_id'] = _notificationBotId;
      }
      config['trend_filter_enabled'] = _trendFilterEnabled;
      config['trend_filter_period'] = _trendFilterPeriod;

      await widget.repository.createRun(config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_strategyDisplayName(_selectedStrategy!.name)} запущена!',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
        context.go('/trading');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingStep = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Настройка стратегии',
      showBackButton: true,
      currentPath: '/trading/wizard',
      body: ConstrainedContent(
        maxWidth: 720,
        child: Column(
        children: [
          _buildProgressBar(),
          Expanded(
            child: _buildStepContent(),
          ),
          _buildNavigation(),
        ],
      ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final pc = PfColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: PfSpacing.md, horizontal: PfSpacing.sm),
      margin: const EdgeInsets.fromLTRB(PfSpacing.lg, PfSpacing.lg, PfSpacing.lg, 0),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? PfColors.cardLight,
        borderRadius: PfRadius.borderRadiusLg,
        border: Border.all(color: pc.borderC),
      ),
      child: Row(
        children: List.generate(9, (index) {
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
                                color: theme.colorScheme.onPrimary,
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
                    // Step label (compact)
                    Text(
                      _stepShortLabels[index],
                      style: PfTypography.caption.copyWith(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : PfColors.mutedForeground,
                        fontSize: isActive ? 10 : 9,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  static const _stepShortLabels = [
    'Режим', 'Пара', 'Страт.', 'Плечо', 'Баланс',
    'Макс.', 'TF', 'Период', 'Старт',
  ];

  Widget _buildStepContent() {
    if (_loadingStep) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildStepWidget(theme, isDark),
    );
  }

  Widget _buildStepWidget(ThemeData theme, bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildStep1Mode(theme);
      case 1:
        return _runMode == RunMode.real
            ? _buildStepExchange(theme)
            : _buildStep2Pair(theme);
      case 2:
        return _buildStep3Strategy(theme);
      case 3:
        return _buildStep4Leverage(theme);
      case 4:
        return _runMode == RunMode.real
            ? const SizedBox.shrink()
            : _buildStep5Balance(theme);
      case 5:
        return _buildStep6MaxTrade(theme);
      case 6:
        return _buildStep7Timeframe(theme);
      case 7:
        return _buildStep8Period(theme, isDark);
      case 8:
        return _buildStep9Summary(theme, isDark);
      default:
        return const SizedBox.shrink();
    }
  }

  // ─── Step 1: Mode ────────────────────────────────────────────────

  Widget _buildStep1Mode(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Выберите режим запуска',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        _modeCard(
          theme: theme,
          emoji: '📜',
          title: 'Исторические данные',
          subtitle: 'Тестирование на исторических данных',
          mode: RunMode.historical,
        ),
        const SizedBox(height: 12),
        _modeCard(
          theme: theme,
          emoji: '💻',
          title: 'Реальные данные',
          subtitle: 'Торговля на виртуальном балансе',
          mode: RunMode.virtual,
        ),
        const SizedBox(height: 12),
        _modeCard(
          theme: theme,
          emoji: '💰',
          title: 'Реальный баланс',
          subtitle: 'Торговля на реальные средства',
          mode: RunMode.real,
        ),
      ],
    );
  }

  Widget _modeCard({
    required ThemeData theme,
    required String emoji,
    required String title,
    required String subtitle,
    required RunMode mode,
  }) {
    final pc = PfColors.of(context);
    final isSelected = _runMode == mode;

    return GestureDetector(
      onTap: () => setState(() => _runMode = mode),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentColor.withValues(alpha: 0.15)
              : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.accentColor
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 16,
                          color: isSelected
                              ? AppTheme.accentColor
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
              onTap: () => _showModeInfo(context, mode),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: pc.mutedC.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: PhosphorIcon(
                    PhosphorIconsFill.question,
                    size: 16,
                    color: theme.textTheme.bodyMedium?.color
                        ?.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get isDark =>
      MediaQuery.of(context).platformBrightness == Brightness.dark;

  void _showModeInfo(BuildContext context, RunMode mode) {
    final (title, description) = switch (mode) {
      RunMode.historical => (
        'Исторические данные',
        'Тестирование стратегии на исторических рыночных данных. '
            'Результаты не влияют на реальный баланс и служат для оптимизации параметров стратегии.',
      ),
      RunMode.virtual => (
        'Реальные данные',
        'Торговля на виртуальном балансе с реальными рыночными данными. '
            'Позволяет проверить стратегию в реальном времени без риска потери средств.',
      ),
      RunMode.real => (
        'Реальный баланс',
        'Торговля на реальные средства с подключением к бирже. '
            'Все сделки исполняются на реальном рынке. Требуется API-ключ биржи.',
      ),
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.2) ?? Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Понятно'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStrategyInfo(StrategyInfo strategy) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.2) ?? Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ),
              const SizedBox(height: 16),
              Text(
                _strategyDisplayName(strategy.name),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                strategy.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withValues(alpha: 0.7),
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.accentColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  strategy.nuances ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.6,
                        fontSize: 14,
                      ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Понятно'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _strategyDisplayName(String name) {
    return switch (name) {
      'hammer' => 'Молот (Hammer)',
      'inverse_hammer' => 'Перевёрнутый Молот (Inverse Hammer)',
      'engulfing' => 'Поглощение (Engulfing)',
      'doji' => 'Доджи (Doji)',
      'three_soldiers' => '3 Солдата / 3 Вороны',
      'ma_crossover' => 'MA Кроссовер',
      'triple_ma' => 'Тройная MA',
      'macd_crossover' => 'MACD Кроссовер',
      'parabolic_sar' => 'Parabolic SAR',
      'adx' => 'ADX',
      'supertrend' => 'Supertrend',
      'rsi_oversold' => 'RSI Перекупленность',
      'stochastic' => 'Стохастик',
      'bollinger_bands' => 'Полосы Боллинджера',
      'keltner_channels' => 'Канал Кельтнера',
      'atr_breakout' => 'ATR Пробой',
      'donchian' => 'Дончиан',
      'vwap' => 'VWAP',
      'obv' => 'OBV',
      'rsi_ma_combo' => 'RSI + MA Комбо',
      'all_pairs_hammer' => '🔍 Hammer на всех парах',
      'all_pairs_inverse_hammer' => '🔍 Inverse Hammer на всех парах',
      _ => name[0].toUpperCase() + name.substring(1),
    };
  }

  Widget _periodChip(int period, ThemeData theme) {
    final isSelected = _trendFilterPeriod == period;
    return GestureDetector(
      onTap: () => setState(() => _trendFilterPeriod = period),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentColor
              : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'SMA$period',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : null,
          ),
        ),
      ),
    );
  }

  // ─── Step 2: Pair ────────────────────────────────────────────────

  Widget _buildStep2Pair(ThemeData theme) {
    // Pair-scanner: show static info instead of pair picker
    if (_isPairScanner) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Торговая пара',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Сканирование всех пар — пара выбирается автоматически',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.accentColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                PhosphorIcon(
                  PhosphorIconsFill.magnifyingGlass,
                  size: 28,
                  color: AppTheme.accentColor,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🔍 Все пары (50 USDT-пар)',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 16,
                          color: AppTheme.accentColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'BTC, ETH, SOL, XRP, ADA и ещё 45 пар',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Выберите торговую пару',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchPairController,
          decoration: InputDecoration(
            hintText: 'Поиск пары...',
            prefixIcon: const PhosphorIcon(
              PhosphorIconsFill.magnifyingGlass,
              size: 20,
            ),
            suffixIcon: _searchPairController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchPairController.clear();
                      _loadPairs(refresh: true);
                    },
                  )
                : null,
          ),
          onChanged: (_) => _loadPairs(refresh: true),
        ),
        const SizedBox(height: 8),
        // Sort toggle
        Row(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _sortByVolume = !_sortByVolume;
                  _pairPage = 1;
                  _hasMorePairs = true;
                  _pairs.clear();
                });
                _loadPairs();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _sortByVolume
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _sortByVolume
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PhosphorIcon(
                      PhosphorIconsFill.arrowDown,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _sortByVolume ? 'По объёму' : 'По умолчанию',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _sortByVolume
                            ? theme.colorScheme.primary
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loadingPairs && _pairs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_pairs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Пары не найдены')),
          )
        else
          ...List.generate(_pairs.length, (index) {
            final pair = _pairs[index];
            final isSelected = _selectedPair?.symbol == pair.symbol;
            return _PairTile(
              pair: pair,
              isSelected: isSelected,
              isLoadingLive: _loadingLiveData,
              liveData: _liveData[pair.symbol],
              onTap: () => setState(() => _selectedPair = pair),
            );
          }),
      ],
    );
  }

  // ─── Step 2 (real): Exchange ─────────────────────────────────────

  Widget _buildStepExchange(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Выберите биржу',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (_exchanges.isEmpty)
          const Center(child: CircularProgressIndicator())
        else
          ...List.generate(_exchanges.length, (index) {
            final exchange = _exchanges[index];
            final isSelected =
                _selectedExchange?.name == exchange.name;
            return GestureDetector(
              onTap: () =>
                  setState(() => _selectedExchange = exchange),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accentColor.withValues(alpha: 0.15)
                      : theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.accentColor
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    PhosphorIcon(
                      PhosphorIconsFill.buildings,
                      size: 24,
                      color: isSelected
                          ? AppTheme.accentColor
                          : theme.textTheme.bodyMedium?.color,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      exchange.displayName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 16,
                        color: isSelected ? AppTheme.accentColor : null,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // ─── Step 3: Strategy ────────────────────────────────────────────

  Widget _buildStep3Strategy(ThemeData theme) {
    final filteredStrategies = _strategies.where((s) {
      final query = _searchStrategyController.text.toLowerCase();
      return query.isEmpty ||
          s.name.toLowerCase().contains(query) ||
          s.description.toLowerCase().contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Выберите стратегию',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchStrategyController,
          decoration: InputDecoration(
            hintText: 'Поиск стратегии...',
            prefixIcon: const PhosphorIcon(
              PhosphorIconsFill.magnifyingGlass,
              size: 20,
            ),
            suffixIcon: _searchStrategyController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _searchStrategyController.clear(),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        if (_loadingStrategies)
          const Center(child: CircularProgressIndicator())
        else if (filteredStrategies.isEmpty)
          Center(
            child: Text(
              'Стратегии не найдены',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          ...List.generate(filteredStrategies.length, (index) {
            final strategy = filteredStrategies[index];
            final isSelected =
                _selectedStrategy?.name == strategy.name;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedStrategy = strategy;
                  // Pair-scanner only works with history mode
                  if (strategy.isPairScanner && _runMode != RunMode.historical) {
                    _runMode = RunMode.historical;
                  }
                });
              },
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accentColor.withValues(alpha: 0.15)
                      : theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.accentColor
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            PhosphorIcon(
                              PhosphorIconsFill.chartLine,
                              size: 20,
                              color: isSelected
                                  ? AppTheme.accentColor
                                  : theme.textTheme.bodyMedium?.color,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _strategyDisplayName(strategy.name),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontSize: 16,
                                color:
                                    isSelected ? AppTheme.accentColor : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strategy.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                    // Info button in top-right corner
                    if (strategy.nuances != null)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () => _showStrategyInfo(strategy),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '?',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accentColor,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ),
            );
          }),
          const SizedBox(height: 24),
          // ── Trend Filter ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PhosphorIcon(
                      PhosphorIconsFill.trendUp,
                      size: 18,
                      color: _trendFilterEnabled ? AppTheme.accentColor : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Трендовый фильтр',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch(
                      value: _trendFilterEnabled,
                      activeColor: AppTheme.accentColor,
                      onChanged: (v) => setState(() => _trendFilterEnabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Вход только при цене выше SMA. Отсекает ложные сигналы на сильном медвежьем рынке.',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
                if (_trendFilterEnabled) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Период SMA:',
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                      ),
                      const SizedBox(width: 12),
                      _periodChip(50, theme),
                      const SizedBox(width: 6),
                      _periodChip(100, theme),
                      const SizedBox(width: 6),
                      _periodChip(200, theme),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // ─── Step 4: Leverage ────────────────────────────────────────────

  Widget _buildStep4Leverage(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Плечо', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Кредитное плечо определяет объём позиции относительно вашего баланса',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            'x${_leverage.toInt()}',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: AppTheme.accentColor,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Slider(
          value: _leverage,
          min: 1,
          max: 100,
          divisions: 99,
          activeColor: AppTheme.accentColor,
          inactiveColor: theme.textTheme.bodyMedium?.color
              ?.withValues(alpha: 0.2),
          onChanged: (v) => setState(() => _leverage = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [1, 2, 3, 5, 10, 25, 50].map((v) {
            final isActive = _leverage == v;
            return ActionChip(
              label: Text('x$v'),
              backgroundColor: isActive
                  ? AppTheme.accentColor
                  : theme.cardTheme.color,
              labelStyle: TextStyle(
                color: isActive ? Colors.white : null,
                fontWeight: isActive ? FontWeight.w600 : null,
              ),
              onPressed: () => setState(() => _leverage = v.toDouble()),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Step 5: Balance ─────────────────────────────────────────────

  Widget _buildStep5Balance(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Баланс', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Стартовый виртуальный баланс для тестирования',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            '\$${_balance.toStringAsFixed(0)}',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: AppTheme.accentColor,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Slider(
          value: _balance,
          min: 100,
          max: 100000,
          divisions: 999,
          activeColor: AppTheme.accentColor,
          inactiveColor: theme.textTheme.bodyMedium?.color
              ?.withValues(alpha: 0.2),
          onChanged: (v) => setState(() => _balance = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [1000, 5000, 10000, 50000, 100000].map((v) {
            final isActive = _balance == v;
            return ActionChip(
              label: Text('\$${(v / 1000).toStringAsFixed(0)}K'),
              backgroundColor: isActive
                  ? AppTheme.accentColor
                  : theme.cardTheme.color,
              labelStyle: TextStyle(
                color: isActive ? Colors.white : null,
                fontWeight: isActive ? FontWeight.w600 : null,
              ),
              onPressed: () =>
                  setState(() => _balance = v.toDouble()),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Step 6: Max Trade ───────────────────────────────────────────

  Widget _buildStep6MaxTrade(ThemeData theme) {
    final maxAllowed = _balance / _leverage;
    if (_maxTrade > maxAllowed) {
      _maxTrade = maxAllowed;
    }
    final presets = [
      maxAllowed * 0.1,
      maxAllowed * 0.25,
      maxAllowed * 0.5,
      maxAllowed * 0.75,
      maxAllowed * 1.0,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Макс. сделка', style: theme.textTheme.titleLarge),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Мера безопасности',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Максимальный объём одной сделки. Ограничение: \$${maxAllowed.toStringAsFixed(0)}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            '\$${_maxTrade.toStringAsFixed(0)}',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: AppTheme.accentColor,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Slider(
          value: _maxTrade,
          min: 1,
          max: maxAllowed > 1 ? maxAllowed : 1,
          divisions: 100,
          activeColor: AppTheme.accentColor,
          inactiveColor: theme.textTheme.bodyMedium?.color
              ?.withValues(alpha: 0.2),
          onChanged: (v) => setState(() => _maxTrade = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((v) {
            final label = v >= 1000
                ? '\$${(v / 1000).toStringAsFixed(1)}K'
                : '\$${v.toStringAsFixed(0)}';
            final isActive = _maxTrade == v;
            return ActionChip(
              label: Text(label),
              backgroundColor: isActive
                  ? AppTheme.accentColor
                  : theme.cardTheme.color,
              labelStyle: TextStyle(
                color: isActive ? Colors.white : null,
                fontWeight: isActive ? FontWeight.w600 : null,
                fontSize: 12,
              ),
              onPressed: () =>
                  setState(() => _maxTrade = v),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Step 7: Timeframe ───────────────────────────────────────────

  Widget _buildStep7Timeframe(ThemeData theme) {
    const allTimeframes = [
      '1m', '5m', '15m', '30m',
      '1h', '4h', '1d', '1w', '30d',
    ];
    // For pair-scanner: only 30m+ timeframes
    final timeframes = _isPairScanner
        ? ['30m', '1h', '4h', '1d', '1w', '30d']
        : allTimeframes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Таймфрейм',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Выберите временной интервал свечей для анализа',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.6,
          ),
          itemCount: timeframes.length,
          itemBuilder: (context, index) {
            final tf = timeframes[index];
            final isSelected = _timeframe == tf;
            return GestureDetector(
              onTap: () => setState(() => _timeframe = tf),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accentColor
                      : theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.accentColor
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    tf,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : theme.textTheme.bodyLarge?.color,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ─── Step 8: Period ──────────────────────────────────────────────

  static const _periodPresets = [
    ('1н', 7),
    ('2н', 14),
    ('1м', 30),
    ('3м', 90),
    ('6м', 180),
    ('1г', 365),
  ];

  DateTime _presetDate(int daysBack) {
    final d = DateTime.now().subtract(Duration(days: daysBack));
    return DateTime(d.year, d.month, d.day);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _displayDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Widget _buildStep8Period(ThemeData theme, bool isDark) {
    final pc = PfColors.of(context);
    if (_runMode == RunMode.historical) {
      final start = _dateRange?.start;
      final end = _dateRange?.end;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Период',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Выберите отрезок дат для исторического тестирования',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),

          // ── Быстрые пресеты ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _periodPresets.map((preset) {
              final label = preset.$1;
              final days = preset.$2;
              // Check if this preset matches current selection
              final matching = start != null && end != null &&
                  _isSameDay(start, _presetDate(days)) &&
                  _isSameDay(end, DateTime.now());
              return ActionChip(
                label: Text(label),
                backgroundColor: matching
                    ? AppTheme.accentColor
                    : theme.cardTheme.color,
                labelStyle: TextStyle(
                  color: matching ? Colors.white : null,
                  fontWeight: matching ? FontWeight.w600 : null,
                  fontSize: 13,
                ),
                side: matching
                    ? BorderSide.none
                    : BorderSide(
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.2) ?? Colors.grey.withValues(alpha: 0.2),
                      ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                onPressed: () {
                  setState(() {
                    _dateRange = DateTimeRange(
                      start: _presetDate(days),
                      end: DateTime.now(),
                    );
                  });
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // ── Свой диапазон (DateRangePicker) ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  initialDateRange: _dateRange ?? DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 7)),
                    end: DateTime.now(),
                  ),
                  firstDate: DateTime(2015),
                  lastDate: DateTime.now(),
                  builder: (context, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.dark(
                        primary: AppTheme.accentColor,
                        surface: AppTheme.surfaceColor,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null && mounted) {
                  setState(() => _dateRange = picked);
                }
              },
              icon: const PhosphorIcon(
                PhosphorIconsFill.calendar,
                size: 18,
              ),
              label: const Text('Свой диапазон'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.2) ?? Colors.grey.withValues(alpha: 0.2),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Выбранный диапазон ──
          if (start != null && end != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  PhosphorIcon(
                    PhosphorIconsFill.info,
                    size: 16,
                    color: AppTheme.accentColor.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${end.difference(start).inDays + 1} дней',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.accentColor.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }

    // Virtual mode
    const durations = [1, 3, 5, 7, 15, 30, 60, 90, 180];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Длительность',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Выберите длительность тестового периода',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: durations.map((days) {
            final isSelected = _duration == days;
            String label;
            if (days < 30) {
              label = '$daysд';
            } else if (days < 365) {
              label = '${days ~/ 30}мес';
            } else {
              label = '${days ~/ 365}г';
            }
            return GestureDetector(
              onTap: () => setState(() => _duration = days),
              child: Container(
                width: (MediaQuery.of(context).size.width - 56) / 3,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accentColor
                      : theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.accentColor
                        : Colors.transparent,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : theme.textTheme.bodyLarge?.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    if (isSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: PhosphorIcon(
                          PhosphorIconsFill.check,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  // ─── Step 9: Summary ─────────────────────────────────────────────

  Widget _buildStep9Summary(ThemeData theme, bool isDark) {
    final pc = PfColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Сводка настроек',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        _summaryRow(theme, 'Режим', _modeLabel(_runMode!)),
        const SizedBox(height: 12),
        if (_runMode == RunMode.real)
          _summaryRow(theme, 'Биржа', _selectedExchange?.displayName ?? '—')
        else
          _summaryRow(theme, 'Пара', _selectedPair?.displayName ?? '—'),
        const SizedBox(height: 12),
        _summaryRow(theme, 'Стратегия', _selectedStrategy?.name ?? '—'),
        const SizedBox(height: 12),
        _summaryRow(theme, 'Плечо', 'x${_leverage.toInt()}'),
        if (_runMode != RunMode.real) ...[
          const SizedBox(height: 12),
          _summaryRow(
              theme, 'Баланс', '\$${_balance.toStringAsFixed(0)}'),
        ],
        const SizedBox(height: 12),
        _summaryRow(
            theme, 'Макс. сделка', '\$${_maxTrade.toStringAsFixed(0)}'),
        const SizedBox(height: 12),
        _summaryRow(theme, 'Таймфрейм', _timeframe ?? '—'),
        const SizedBox(height: 12),
        if (_runMode == RunMode.historical && _dateRange != null)
          _summaryRow(
            theme,
            'Период',
            '${_formatDate(_dateRange!.start)} — ${_formatDate(_dateRange!.end)}',
          ),
        if (_runMode == RunMode.virtual && _duration != null)
          _summaryRow(
            theme,
            'Длительность',
            '$_duration дн.',
          ),
        const SizedBox(height: 12),
        _summaryRow(theme, 'Тренд. фильтр', _trendFilterEnabled ? 'Вкл (SMA$_trendFilterPeriod)' : 'Выкл'),
        const SizedBox(height: 24),

        // ── Notification settings ──
        Text(
          'Уведомления',
          style: PfTypography.titleMd.copyWith(color: PfColors.foreground),
        ),
        const SizedBox(height: PfSpacing.sm),
        PfCard(
          padding: const EdgeInsets.symmetric(horizontal: PfSpacing.md, vertical: PfSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Уведомления о сделках', style: PfTypography.bodyMd.copyWith(color: PfColors.foreground)),
                    const SizedBox(height: 2),
                    Text(
                      'Получать уведомления о каждой сделке в Telegram',
                      style: PfTypography.bodySm.copyWith(color: PfColors.mutedForeground),
                    ),
                  ],
                ),
              ),
              // ── Custom toggle вместо стандартного Switch ──
              GestureDetector(
                onTap: () {
                  setState(() => _notifyTrades = !_notifyTrades);
                  if (_notifyTrades && _bots.isEmpty) {
                    _loadBots();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 28,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _notifyTrades
                        ? PfColors.accentTrading
                        : PfColors.muted,
                    borderRadius: PfRadius.borderRadiusPill,
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: _notifyTrades
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _notifyTrades
                            ? Theme.of(context).colorScheme.primary
                            : pc.mutedForegroundC,
                        borderRadius: PfRadius.borderRadiusPill,
                        boxShadow: [
                          BoxShadow(
                            color: pc.foregroundC.withValues(alpha: 0.15),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_notifyTrades) ...[
          const SizedBox(height: 8),
          if (_loadingBots)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_bots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Нет доступных Telegram ботов. Добавьте бота в настройках.',
                style: TextStyle(
                  color: pc.warningC,
                  fontSize: 13,
                ),
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: _notificationBotId,
              decoration: InputDecoration(
                labelText: 'Telegram бот',
                prefixIcon: const Icon(PhosphorIconsFill.robot, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: pc.borderC,
                  ),
                ),
              ),
              items: _bots.map((bot) {
                return DropdownMenuItem(
                  value: bot.id,
                  child: Text(bot.name),
                );
              }).toList(),
              onChanged: (v) => setState(() => _notificationBotId = v),
              validator: (_notifyTrades && _notificationBotId == null)
                  ? (v) => 'Выберите бота'
                  : null,
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _summaryRow(ThemeData theme, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _modeLabel(RunMode mode) {
    return switch (mode) {
      RunMode.historical => 'Исторические данные 📜',
      RunMode.virtual => 'Реальные данные 💻',
      RunMode.real => 'Реальный баланс 💰',
    };
  }

  // ─── Navigation ──────────────────────────────────────────────────

  Widget _buildNavigation() {
    return Container(
      padding: const EdgeInsets.all(PfSpacing.md),
      margin: const EdgeInsets.symmetric(horizontal: PfSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? PfColors.cardLight,
        borderRadius: PfRadius.borderRadiusXl,
        border: const Border(
          top: BorderSide(color: PfColors.border),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: PfButton(
                variant: 'outline',
                size: 'lg',
                label: 'Назад',
                icon: PhosphorIconsFill.caretLeft,
                onPressed: _prevStep,
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: PfSpacing.md),
          Expanded(
            child: PfButton(
              variant: 'primary',
              size: 'lg',
              label: _currentStep < 8 ? 'Далее' : 'Запустить',
              icon: _currentStep < 8
                  ? PhosphorIconsFill.caretRight
                  : PhosphorIconsFill.rocket,
              iconEnd: true,
              expanded: true,
              onPressed: _canProceed
                  ? (_currentStep < 8 ? _nextStep : _submitRun)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pair Tile ─────────────────────────────────────────────────────

class _PairTile extends StatelessWidget {
  final TradingPair pair;
  final bool isSelected;
  final bool isLoadingLive;
  final PairLiveData? liveData;
  final VoidCallback onTap;

  const _PairTile({
    required this.pair,
    required this.isSelected,
    required this.onTap,
    this.isLoadingLive = false,
    this.liveData,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : Theme.of(context).cardTheme.color ?? PfColors.cardLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 36,
                height: 36,
                child: pair.iconUrl != null
                    ? Image.network(
                        pair.iconUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _coinLetterBox(theme),
                        loadingBuilder: (_, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _coinLetterBox(theme);
                        },
                      )
                    : _coinLetterBox(theme),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pair.base}/${pair.quote}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 15,
                      color: isSelected ? Theme.of(context).colorScheme.primary : null,
                    ),
                  ),
                  Text(
                    pair.symbol,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            // Live data column
            if (isLoadingLive)
              _skeletonColumn(theme)
            else if (liveData != null) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatPrice(liveData!.price),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatChange(liveData!.change24h),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: liveData!.change24h >= 0
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatVolume(liveData!.volume),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: PhosphorIcon(
                  PhosphorIconsFill.check,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _coinLetterBox(ThemeData theme) {
    final symbol = pair.base.toLowerCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/icons/crypto/$symbol.png',
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : theme.disabledColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              pair.base.substring(0, 1),
              style: TextStyle(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.textTheme.bodyLarge?.color?.withValues(alpha: 0.7),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    if (price >= 1000) return '\$${(price / 1000).toStringAsFixed(1)}K';
    if (price >= 1) return '\$${price.toStringAsFixed(2)}';
    if (price >= 0.01) return '\$${price.toStringAsFixed(4)}';
    return '\$${price.toStringAsFixed(6)}';
  }

  String _formatChange(double change) {
    final sign = change >= 0 ? '+' : '';
    return '$sign${change.toStringAsFixed(2)}%';
  }

  String _formatVolume(double volume) {
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

  Widget _skeletonColumn(ThemeData theme) {
    return Column(
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
    );
  }
}
