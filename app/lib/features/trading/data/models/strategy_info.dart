class StrategyInfo {
  final String name;
  final String description;
  final String type;
  final String? nuances;
  final bool isPairScanner;

  const StrategyInfo({
    required this.name,
    required this.description,
    required this.type,
    this.nuances,
    this.isPairScanner = false,
  });

  factory StrategyInfo.fromJson(Map<String, dynamic> json) {
    return StrategyInfo(
      name: json['name'] as String,
      description: json['description'] as String,
      type: json['type'] as String,
      nuances: json['nuances'] as String?,
      isPairScanner: json['is_pair_scanner'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'type': type,
        if (nuances != null) 'nuances': nuances,
        'is_pair_scanner': isPairScanner,
      };
}
