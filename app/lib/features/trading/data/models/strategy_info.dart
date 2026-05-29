class StrategyInfo {
  final String name;
  final String description;
  final String type;
  final String? nuances;

  const StrategyInfo({
    required this.name,
    required this.description,
    required this.type,
    this.nuances,
  });

  factory StrategyInfo.fromJson(Map<String, dynamic> json) {
    return StrategyInfo(
      name: json['name'] as String,
      description: json['description'] as String,
      type: json['type'] as String,
      nuances: json['nuances'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'type': type,
        if (nuances != null) 'nuances': nuances,
      };
}
