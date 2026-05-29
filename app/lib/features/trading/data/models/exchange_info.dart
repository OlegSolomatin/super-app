class ExchangeInfo {
  final String name;
  final String displayName;

  const ExchangeInfo({
    required this.name,
    required this.displayName,
  });

  factory ExchangeInfo.fromJson(Map<String, dynamic> json) {
    return ExchangeInfo(
      name: json['name'] as String,
      displayName: json['display_name'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'display_name': displayName,
      };
}
