/// Live 24hr market data for a trading pair.
class PairLiveData {
  final double price;
  final double volume;
  final double change24h;

  const PairLiveData({
    required this.price,
    required this.volume,
    required this.change24h,
  });

  factory PairLiveData.fromJson(Map<String, dynamic> json) {
    return PairLiveData(
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
      change24h: (json['change_24h'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'price': price,
        'volume': volume,
        'change_24h': change24h,
      };
}
