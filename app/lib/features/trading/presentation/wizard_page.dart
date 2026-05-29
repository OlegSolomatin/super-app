import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/theme.dart';

class TradingWizardPage extends StatefulWidget {
  const TradingWizardPage({super.key});

  @override
  State<TradingWizardPage> createState() => _TradingWizardPageState();
}

class _TradingWizardPageState extends State<TradingWizardPage> {
  int _currentStep = 0;

  static const _stepLabels = [
    'Биржа',
    'Пара',
    'Стратегия',
    'Индикаторы',
    'Риски',
    'Таймфрейм',
    'Период',
    'Баланс',
    'Запуск',
  ];

  static const _stepIcons = [
    Icons.account_balance,
    Icons.currency_bitcoin,
    Icons.analytics,
    Icons.tune,
    Icons.shield,
    Icons.timeline,
    Icons.date_range,
    Icons.account_balance_wallet,
    Icons.rocket_launch,
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Торговый мастер'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Step indicator
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.surfaceColor
                  : AppTheme.lightSurfaceColor,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Row(
              children: List.generate(_stepLabels.length, (index) {
                final isActive = index == _currentStep;
                final isDone = index < _currentStep;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentStep = index),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? AppTheme.accentColor
                                : isDone
                                    ? const Color(0xFF4CAF50)
                                    : isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.black.withValues(alpha: 0.1),
                          ),
                          child: Center(
                            child: isDone
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : isDark
                                              ? Colors.white54
                                              : Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _stepLabels[index],
                          style: TextStyle(
                            color: isActive
                                ? AppTheme.accentColor
                                : isDark
                                    ? Colors.white54
                                    : Colors.black54,
                            fontSize: 9,
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
          ),
          // Step content
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _stepIcons[_currentStep],
                      size: 64,
                      color: AppTheme.accentColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Шаг ${_currentStep + 1}: ${_stepLabels[_currentStep]}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Настройка будет доступна в следующем обновлении',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Navigation buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.surfaceColor
                  : AppTheme.lightSurfaceColor,
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
                      onPressed: () =>
                          setState(() => _currentStep--),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Назад'),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _currentStep < _stepLabels.length - 1
                        ? () => setState(() => _currentStep++)
                        : () {
                            context.go('/');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Запуск бэктеста — скоро!'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                    icon: Icon(
                      _currentStep < _stepLabels.length - 1
                          ? Icons.arrow_forward
                          : Icons.rocket_launch,
                    ),
                    label: Text(
                      _currentStep < _stepLabels.length - 1
                          ? 'Далее'
                          : 'Запустить',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
