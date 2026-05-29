class StrategyInfo {
  final String name;
  final String description;
  final String type;

  const StrategyInfo({
    required this.name,
    required this.description,
    required this.type,
  });

  factory StrategyInfo.fromJson(Map<String, dynamic> json) {
    return StrategyInfo(
      name: json['name'] as String,
      description: json['description'] as String,
      type: json['type'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'type': type,
      };
}
