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
      side: json['side'] as String,
      price: (json['price'] as num).toDouble(),
      time: DateTime.parse(json['time'] as String),
      pnl: (json['pnl'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'side': side,
        'price': price,
        'time': time.toIso8601String(),
        'pnl': pnl,
      };

  bool get isBuy => side == 'buy';
  bool get isSell => side == 'sell';
}
