class TradingTrade {
  final String side;
  final double price;
  final DateTime time;
  final double pnl;

  const TradingTrade({
    required this.side,
    required this.price,
    required this.time,
    required this.pnl,
  });

  factory TradingTrade.fromJson(Map<String, dynamic> json) {
    return TradingTrade(
      side: json['side'] as String? ?? 'BUY',
      price: (json['entry_price'] as num?)?.toDouble() ?? 0.0,
      time: json['entry_time'] != null
          ? DateTime.parse(json['entry_time'] as String)
          : DateTime.now(),
      pnl: (json['pnl'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'side': side,
        'price': price,
        'time': time.toIso8601String(),
        'pnl': pnl,
      };

  bool get isBuy => side.toUpperCase() == 'BUY';
  bool get isSell => side.toUpperCase() == 'SELL';
}
