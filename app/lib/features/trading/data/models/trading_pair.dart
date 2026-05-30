class TradingPair {
  final String symbol;
  final String base;
  final String quote;
  final String? iconUrl;

  const TradingPair({
    required this.symbol,
    required this.base,
    required this.quote,
    this.iconUrl,
  });

  factory TradingPair.fromJson(Map<String, dynamic> json) {
    return TradingPair(
      symbol: json['symbol'] as String,
      base: json['base'] as String,
      quote: json['quote'] as String,
      iconUrl: json['icon_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'base': base,
        'quote': quote,
        if (iconUrl != null) 'icon_url': iconUrl,
      };

  String get displayName => '$base/$quote';
}
