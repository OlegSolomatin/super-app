import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/theme.dart';
import 'package:app/features/trading/data/models/trading_pair.dart';
import 'package:app/features/trading/data/models/strategy_info.dart';
import 'package:app/features/trading/data/models/exchange_info.dart';
import 'package:app/features/trading/data/trading_repository.dart';
import 'package:app/shared/widgets/responsive_layout.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/settings/data/settings_repository.dart';

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

  // Step 3
  List<StrategyInfo> _strategies = [];
  StrategyInfo? _selectedStrategy;
  bool _loadingStrategies = false;

  // Step 4
  double _leverage = 1;
  double _stopLossPercent = 2.0;
  double _takeProfitPercent = 5.0;

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

  @override
  void initState() {
    super.initState();
    _loadStrategies();
  }

  @override
  void dispose() {
    _searchPairController.dispose();
    _searchStrategyController.dispose();
    super.dispose();
  }

  Future<void> _loadPairs({bool refresh = false}) async {
    if (_loadingPairs) return;
    if (refresh) {
      _pairPage = 1;
      _hasMorePairs = true;
      _pairs.clear();
    }
    setState(() => _loadingPairs = true);
    try {
      final result = await widget.repository.getPairs(
        search: _searchPairController.text.isNotEmpty
            ? _searchPairController.text
            : null,
        page: _pairPage,
        pageSize: 50,
      );
      if (mounted) {
        setState(() {
          _pairs.addAll(result.items);
          _hasMorePairs = _pairs.length < result.total;
          _loadingPairs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPairs = false);
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
        (_selectedPair != null ||
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
        return _runMode == RunMode.real
            ? _selectedExchange != null
            : _selectedPair != null;
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
        config['pair'] = _selectedPair!.symbol;
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
      config['stop_loss_percent'] = _stopLossPercent;
      config['take_profit_percent'] = _takeProfitPercent;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Настройка стратегии'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const PhosphorIcon(PhosphorIconsFill.caretLeft),
          onPressed: () {
            if (_currentStep > 0) {
              _prevStep();
            } else {
              context.go('/trading');
            }
          },
        ),
      ),
      body: ConstrainedContent(
        child: Column(
        children: [
          _buildProgressBar(theme, isDark),
          Expanded(
            child: _buildStepContent(theme, isDark),
          ),
          _buildNavigation(theme, isDark),
        ],
      ),
      ),
    );
  }

  Widget _buildProgressBar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: List.generate(9, (index) {
          final isActive = index == _currentStep;
          final isDone = index < _currentStep;
          return Expanded(
            child: GestureDetector(
              onTap: () => _onStepTapped(index),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone
                          ? const Color(0xFF4CAF50)
                          : isActive
                              ? AppTheme.accentColor
                              : isDark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : Colors.black.withValues(alpha: 0.1),
                    ),
                    child: Center(
                      child: isDone
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stepShortLabels[index],
                    style: TextStyle(
                      color: isActive
                          ? AppTheme.accentColor
                          : isDark
                              ? Colors.white54
                              : Colors.black54,
                      fontSize: 8,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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

  Widget _buildStepContent(ThemeData theme, bool isDark) {
    if (_loadingStep) {
      return const Center(child: CircularProgressIndicator());
    }

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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05),
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
                  color: Colors.white.withValues(alpha: 0.2),
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
                    color: Colors.white.withValues(alpha: 0.2),
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
      _ => name[0].toUpperCase() + name.substring(1),
    };
  }

  // ─── Step 2: Pair ────────────────────────────────────────────────

  Widget _buildStep2Pair(ThemeData theme) {
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
        const SizedBox(height: 16),
        Expanded(
          child: _loadingPairs && _pairs.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _pairs.isEmpty
                  ? Center(
                      child: Text(
                        'Пары не найдены',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollEndNotification &&
                            notification.metrics.pixels >=
                                notification.metrics.maxScrollExtent - 100 &&
                            _hasMorePairs &&
                            !_loadingPairs) {
                          _pairPage++;
                          _loadPairs();
                        }
                        return false;
                      },
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _pairs.length +
                            (_hasMorePairs ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _pairs.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          final pair = _pairs[index];
                          final isSelected =
                              _selectedPair?.symbol == pair.symbol;
                          return _PairTile(
                            pair: pair,
                            isSelected: isSelected,
                            onTap: () =>
                                setState(() => _selectedPair = pair),
                          );
                        },
                      ),
                    ),
        ),
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
              onTap: () =>
                  setState(() => _selectedStrategy = strategy),
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
                                '!',
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
        const SizedBox(height: 24),
        // ── Stop Loss ──
        Text(
          'Стоп-лосс',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Сделка закроется, если цена упадёт на ${_stopLossPercent.toStringAsFixed(1)}%',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(PhosphorIconsFill.trendDown, size: 18, color: Color(0xFFE53935)),
            Expanded(
              child: Slider(
                value: _stopLossPercent,
                min: 0.5,
                max: 10,
                divisions: 19,
                activeColor: const Color(0xFFE53935),
                inactiveColor: theme.textTheme.bodyMedium?.color
                    ?.withValues(alpha: 0.2),
                onChanged: (v) => setState(() => _stopLossPercent = v),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '${_stopLossPercent.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Color(0xFFE53935),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // ── Take Profit ──
        Text(
          'Тейк-профит',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Сделка закроется, если цена вырастет на ${_takeProfitPercent.toStringAsFixed(1)}%',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(PhosphorIconsFill.trendUp, size: 18, color: Color(0xFF4CAF50)),
            Expanded(
              child: Slider(
                value: _takeProfitPercent,
                min: 1.0,
                max: 50,
                divisions: 49,
                activeColor: const Color(0xFF4CAF50),
                inactiveColor: theme.textTheme.bodyMedium?.color
                    ?.withValues(alpha: 0.2),
                onChanged: (v) => setState(() => _takeProfitPercent = v),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '${_takeProfitPercent.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
    const timeframes = [
      '1m', '5m', '15m', '30m',
      '1h', '4h', '1d', '1w', '30d',
    ];

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
        const SizedBox(height: 24),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
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
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.accentColor
                        : Colors.transparent,
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
                      fontSize: 16,
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

  Widget _buildStep8Period(ThemeData theme, bool isDark) {
    if (_runMode == RunMode.historical) {
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
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2015),
                lastDate: DateTime.now(),
                initialDateRange: _dateRange,
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.dark(
                        primary: AppTheme.accentColor,
                        surface: AppTheme.surfaceColor,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() => _dateRange = picked);
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  PhosphorIcon(
                    PhosphorIconsFill.calendar,
                    size: 24,
                    color: AppTheme.accentColor,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dateRange != null
                              ? '${_formatDate(_dateRange!.start)} — ${_formatDate(_dateRange!.end)}'
                              : 'Нажмите для выбора дат',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 15,
                            color: _dateRange != null
                                ? null
                                : theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        if (_dateRange != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${_dateRange!.end.difference(_dateRange!.start).inDays + 1} дней',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const PhosphorIcon(
                    PhosphorIconsFill.caretRight,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Сводка настроек',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        _summaryRow(theme, 'Режим', _modeLabel(_runMode!)),
        const Divider(
            color: Colors.white24, height: 1, indent: 0, endIndent: 0),
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
        const SizedBox(height: 24),

        // ── Notification settings ──
        Text(
          'Уведомления',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : null,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Уведомления о сделках'),
          subtitle: Text(
            'Получать уведомления о каждой сделке в Telegram',
            style: theme.textTheme.bodySmall,
          ),
          value: _notifyTrades,
          activeColor: AppTheme.accentColor,
          onChanged: (v) {
            setState(() => _notifyTrades = v);
            if (v && _bots.isEmpty) {
              _loadBots();
            }
          },
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
                  color: Colors.orange.shade300,
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
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.12),
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
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _loadingStep ? null : _submitRun,
            icon: _loadingStep
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const PhosphorIcon(
                    PhosphorIconsFill.rocket,
                    size: 22,
                  ),
            label: Text(
              _loadingStep ? 'Запуск...' : 'Запустить',
              style: const TextStyle(
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

  Widget _buildNavigation(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceColor : AppTheme.lightSurfaceColor,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _prevStep,
                icon: const PhosphorIcon(
                  PhosphorIconsFill.caretLeft,
                  size: 18,
                ),
                label: const Text('Назад'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentColor,
                  side: const BorderSide(color: AppTheme.accentColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: const Size(0, 50),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _currentStep < 8
                  ? (_canProceed ? _nextStep : null)
                  : (_canProceed ? _submitRun : null),
              icon: PhosphorIcon(
                _currentStep < 8
                    ? PhosphorIconsFill.caretRight
                    : PhosphorIconsFill.rocket,
                size: 18,
              ),
              label: Text(
                _currentStep < 8 ? 'Далее' : 'Запустить',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _canProceed
                    ? AppTheme.accentColor
                    : theme.textTheme.bodyMedium?.color
                        ?.withValues(alpha: 0.3),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
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
  final VoidCallback onTap;

  const _PairTile({
    required this.pair,
    required this.isSelected,
    required this.onTap,
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
              ? AppTheme.accentColor.withValues(alpha: 0.15)
              : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : Colors.transparent,
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
                      color: isSelected ? AppTheme.accentColor : null,
                    ),
                  ),
                  Text(
                    pair.symbol,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const PhosphorIcon(
                PhosphorIconsFill.check,
                size: 20,
                color: AppTheme.accentColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _coinLetterBox(ThemeData theme) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.accentColor.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          pair.base.substring(0, 1),
          style: TextStyle(
            color: isSelected ? AppTheme.accentColor : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
