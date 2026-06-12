/// Model for a trading signal from Telegram screener channels.
class TradingSignal {
  final int id;
  final String channel;
  final String exchange;
  final String pair;
  final double? priceRange;
  final double? vol60m;
  final double? vol10m;
  final double? slope;
  final double? topRatio;
  final double? botRatio;
  final String? mappedStrategy;
  final String? mappedEngine;
  final String? signalLabel;
  final String? signalType;
  final double? confidence;
  final String? mappedExchangeFallback;
  final Map<String, dynamic>? mappedParams;
  final Map<String, bool>? mappedAvailableExchanges;
  final bool isProcessed;
  final DateTime? createdAt;

  TradingSignal({
    required this.id,
    required this.channel,
    required this.exchange,
    required this.pair,
    this.priceRange,
    this.vol60m,
    this.vol10m,
    this.slope,
    this.topRatio,
    this.botRatio,
    this.mappedStrategy,
    this.mappedEngine,
    this.signalLabel,
    this.signalType,
    this.confidence,
    this.mappedExchangeFallback,
    this.mappedParams,
    this.mappedAvailableExchanges,
    this.isProcessed = false,
    this.createdAt,
  });

  factory TradingSignal.fromJson(Map<String, dynamic> json) {
    final m = json['mapped_params'];
    return TradingSignal(
      id: json['id'] as int,
      channel: json['channel'] as String? ?? '',
      exchange: json['exchange'] as String? ?? '',
      pair: json['pair'] as String? ?? '',
      priceRange: _toDouble(json['price_range']),
      vol60m: _toDouble(json['vol_60m']),
      vol10m: _toDouble(json['vol_10m']),
      slope: _toDouble(json['slope']),
      topRatio: _toDouble(json['top_ratio']),
      botRatio: _toDouble(json['bot_ratio']),
      mappedStrategy: json['mapped_strategy'] as String?,
      mappedEngine: json['mapped_engine'] as String?,
      signalLabel: json['signal_label'] as String? ?? json['signal_type'] as String?,
      signalType: json['signal_type'] as String?,
      confidence: _toDouble(json['confidence']),
      mappedExchangeFallback: json['mapped_exchange_fallback'] as String?,
      mappedParams: m is Map<String, dynamic> ? m : null,
      mappedAvailableExchanges: _parseStringBoolMap(json['mapped_available_exchanges']),
      isProcessed: json['is_processed'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static Map<String, bool>? _parseStringBoolMap(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, bool>) return v;
    if (v is Map) {
      return v.map((k, v) => MapEntry(k.toString(), v == true));
    }
    return null;
  }

  /// Human-readable time ago string.
  String get timeAgo {
    if (createdAt == null) return '';
    final diff = DateTime.now().toUtc().difference(createdAt!);
    if (diff.inSeconds < 60) return '${diff.inSeconds}с';
    if (diff.inMinutes < 60) return '${diff.inMinutes}м';
    return '${diff.inHours}ч';
  }

  /// Label for the signal type (emoji + name).
  String get typeLabel {
    if (signalLabel != null) return signalLabel!;
    switch (channel) {
      case 'brushscreener':
        if (topRatio != null && botRatio != null) {
          if (topRatio! > botRatio! * 1.5) return 'Дисбаланс ⬇';
          if (botRatio! > topRatio! * 1.5) return 'Дисбаланс ⬆';
        }
        return 'Ёршик';
      case 'stairscreener':
        return 'Лесенка';
      default:
        return 'Сигнал';
    }
  }

  /// Emoji for the signal type.
  String get typeEmoji {
    switch (signalType ?? channel) {
      case 'brush':
        return '🧹';
      case 'stair':
        return '🪜';
      case 'imbalance_top':
        return '⬇️';
      case 'imbalance_bot':
        return '⬆️';
      case 'volume_spike':
        return '🌊';
      default:
        return '🔔';
    }
  }

  /// Engine name for display.
  String get engineLabel {
    if (mappedEngine == 'ob') return 'OrderBook';
    if (mappedEngine == 'trading') return 'Trading';
    return '?';
  }
}
