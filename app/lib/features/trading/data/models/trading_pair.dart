class TradingPair {
  final String symbol;
  final String base;
  final String quote;

  const TradingPair({
    required this.symbol,
    required this.base,
    required this.quote,
  });

  factory TradingPair.fromJson(Map<String, dynamic> json) {
    return TradingPair(
      symbol: json['symbol'] as String,
      base: json['base'] as String,
      quote: json['quote'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'base': base,
        'quote': quote,
      };

  String get displayName => '$base/$quote';
}
