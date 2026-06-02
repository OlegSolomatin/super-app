class TradingTrade {
  final String side;
  final String? pair;
  final double entryPrice;
  final double? exitPrice;
  final DateTime entryTime;
  final DateTime? exitTime;
  final double quantity;
  final double pnl;
  final String status;

  const TradingTrade({
    required this.side,
    this.pair,
    required this.entryPrice,
    this.exitPrice,
    required this.entryTime,
    this.exitTime,
    this.quantity = 0.0,
    required this.pnl,
    this.status = 'closed',
  });

  factory TradingTrade.fromJson(Map<String, dynamic> json) {
    return TradingTrade(
      side: json['side'] as String? ?? 'BUY',
      pair: json['pair'] as String?,
      entryPrice: (json['entry_price'] as num?)?.toDouble() ?? 0.0,
      exitPrice: (json['exit_price'] as num?)?.toDouble(),
      entryTime: json['entry_time'] != null
          ? DateTime.parse(json['entry_time'] as String)
          : DateTime.now(),
      exitTime: json['exit_time'] != null
          ? DateTime.parse(json['exit_time'] as String)
          : null,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      pnl: (json['pnl'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'closed',
    );
  }

  Map<String, dynamic> toJson() => {
        'side': side,
        'pair': pair,
        'entry_price': entryPrice,
        'exit_price': exitPrice,
        'entry_time': entryTime.toIso8601String(),
        'exit_time': exitTime?.toIso8601String(),
        'quantity': quantity,
        'pnl': pnl,
        'status': status,
      };

  bool get isBuy => side.toUpperCase() == 'BUY';
  bool get isSell => side.toUpperCase() == 'SELL';

  /// Human-readable entry date
  String get entryDate {
    final d = entryTime.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  /// Human-readable entry time
  String get entryTimeStr {
    final d = entryTime.toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// Human-readable exit date+time, or '—'
  String get exitDateTimeStr {
    if (exitTime == null) return '—';
    final d = exitTime!.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
