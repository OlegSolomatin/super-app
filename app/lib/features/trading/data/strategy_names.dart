/// Маппинг ID стратегий → русские названия.
const Map<String, String> strategyRussianNames = {
  // Свечные паттерны
  'hammer': 'Молот (Hammer)',
  'inverse_hammer': 'Перевёрнутый Молот',
  'engulfing': 'Поглощение (Engulfing)',
  'doji': 'Доджи (Doji)',
  'three_soldiers': '3 Солдата / 3 Вороны',

  // Трендовые
  'ma_crossover': 'MA Кроссовер',
  'triple_ma': 'Тройная MA',
  'macd_crossover': 'MACD Кроссовер',
  'parabolic_sar': 'Parabolic SAR',
  'adx': 'ADX',
  'supertrend': 'Supertrend',

  // Моментум / Осцилляторы
  'rsi_oversold': 'RSI Перекупленность',
  'stochastic': 'Стохастик',

  // Волатильность / Пробои
  'bollinger_bands': 'Полосы Боллинджера',
  'keltner_channels': 'Канал Кельтнера',
  'atr_breakout': 'ATR Пробой',
  'donchian': 'Дончиан',

  // Другие
  'vwap': 'VWAP',
  'obv': 'OBV',

  // Сканеры (молот на всех парах)
  'all_pairs_hammer': 'Hammer (все пары)',
  'all_pairs_inverse_hammer': 'Перев. Молот (все пары)',

  // OrderBook стратегии
  'imbalance': 'Дисбаланс стакана',
  'spread_capture': 'Ловля спреда',
  'order_flow_momentum': 'Моментум потока',
  'market_making': 'Маркет-мейкинг',
};

/// Маппинг ключей конфига стратегии → русские названия.
const Map<String, String> configKeyRussianNames = {
  'strategy': 'Стратегия',
  'pair': 'Пара',
  'timeframe': 'Таймфрейм',
  'virtual_balance': 'Стартовый баланс',
  'duration_days': 'Длительность (дни)',
  'leverage': 'Плечо',
  'exchange': 'Биржа',
  'rsi_period': 'Период RSI',
  'fast_ma': 'Быстрая MA',
  'slow_ma': 'Медленная MA',
  'signal_ma': 'Сигнальная MA',
  'atr_period': 'Период ATR',
  'atr_multiplier': 'Множитель ATR',
  'min_confidence': 'Мин. уверенность',
  'bb_period': 'Период Bollinger',
  'bb_std': 'Стд. откл. Bollinger',
  'keltner_period': 'Период Кельтнера',
  'keltner_atr': 'ATR Кельтнера',
  'donchian_period': 'Период Дончиана',
  'adx_period': 'Период ADX',
  'adx_threshold': 'Порог ADX',
  'sma_period': 'Период SMA',
  'lookback': 'Lookback период',
  'volume_period': 'Период объёма',
  'min_volume_ratio': 'Мин. коэфф. объёма',
  'max_spread_pct': 'Макс. спред (%)',
  'order_book_depth': 'Глубина стакана',
  'imbalance_ratio': 'Коэфф. дисбаланса',
  'min_burst_size': 'Мин. размер всплеска',
  'burst_window_sec': 'Окно всплеска (сек)',
  'spread_threshold_pct': 'Порог спреда (%)',
  'min_spread_profit': 'Мин. профит спреда',
  'order_size_pct': 'Размер ордера (%)',
  'min_quote_volume': 'Мин. объём котировки',
  'entry_mode': 'Режим входа',
  'exit_mode': 'Режим выхода',
  'max_runtime_hours': 'Макс. время (часы)',
  'auto_stop_hours': 'Автостоп (часы)',
  'model': 'Модель',
  'stop_loss_pct': 'Стоп-лосс (%)',
  'take_profit_pct': 'Тейк-профит (%)',
  'trailing_stop_pct': 'Трейлинг стоп (%)',
  'max_open_positions': 'Макс. открытых позиций',
  'min_notional': 'Мин. номинал',

  // OrderBook общие
  'initial_balance': 'Стартовый баланс',
  'max_open_trades': 'Макс. сделок',
  'stoploss': 'Стоп-лосс (%)',
  'trailing_stop': 'Трейлинг стоп (%)',
  'trailing_offset': 'Отступ трейлинга (%)',
  'max_hold_seconds': 'Макс. удержание (сек)',
  'confirmation_ticks': 'Тиков подтверждения',
  'max_spread': 'Макс. спред (%)',
  'cooldown_seconds': 'Кулдаун (сек)',

  // Spread Capture
  'min_spread_pct': 'Мин. спред (%)',
  'spread_entry_threshold': 'Порог входа (спред)',
  'spread_exit_threshold': 'Порог выхода (спред)',

  // Order Flow Momentum
  'flow_threshold_volume': 'Порог объёма потока',
  'min_flow_signals': 'Мин. сигналов потока',
  'flow_exit_seconds': 'Выход потока (сек)',
};

/// Форматирует значение настройки для отображения.
String formatConfigValue(dynamic value) {
  if (value == null) return '—';
  if (value is double) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }
  if (value is bool) return value ? 'Да' : 'Нет';
  return value.toString();
}

/// Возвращает русское название настройки по ключу конфига.
String translateConfigKey(String key) {
  return configKeyRussianNames[key] ?? key;
}

/// Возвращает русское название стратегии или английское, если перевода нет.
String translateStrategy(String? strategyId) {
  if (strategyId == null) return 'Неизвестная';
  return strategyRussianNames[strategyId] ?? strategyId;
}
