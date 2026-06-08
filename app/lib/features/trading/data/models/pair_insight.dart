/// Recommendation score for a strategy based on pair market data.
class StrategyScore {
  final String name;
  final String label;
  final double score;
  final String reason;

  const StrategyScore({
    required this.name,
    required this.label,
    required this.score,
    required this.reason,
  });

  factory StrategyScore.fromJson(Map<String, dynamic> json) {
    return StrategyScore(
      name: json['name'] as String,
      label: json['label'] as String,
      score: (json['score'] as num).toDouble(),
      reason: json['reason'] as String,
    );
  }
}

/// Market insight for a specific pair with strategy recommendations.
class PairInsight {
  final String symbol;
  final double price;
  final double volume24h;
  final double volatility24h;
  final double spread;
  final List<StrategyScore> recommendedStrategies;

  const PairInsight({
    required this.symbol,
    required this.price,
    required this.volume24h,
    required this.volatility24h,
    required this.spread,
    required this.recommendedStrategies,
  });

  factory PairInsight.fromJson(Map<String, dynamic> json) {
    return PairInsight(
      symbol: json['symbol'] as String,
      price: (json['price'] as num).toDouble(),
      volume24h: (json['volume_24h'] as num).toDouble(),
      volatility24h: (json['volatility_24h'] as num).toDouble(),
      spread: (json['spread'] as num).toDouble(),
      recommendedStrategies: (json['recommended_strategies'] as List)
          .map((e) => StrategyScore.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
