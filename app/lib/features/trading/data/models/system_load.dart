/// System load metrics — CPU, RAM, API usage.
class SystemLoad {
  final double cpuPercent;
  final double ramGb;
  final double apiUsagePercent;
  final int activeObRuns;
  final int activeTradingRuns;
  final List<String> warnings;

  const SystemLoad({
    required this.cpuPercent,
    required this.ramGb,
    required this.apiUsagePercent,
    required this.activeObRuns,
    required this.activeTradingRuns,
    this.warnings = const [],
  });

  factory SystemLoad.fromJson(Map<String, dynamic> json) {
    return SystemLoad(
      cpuPercent: (json['cpu_percent'] as num).toDouble(),
      ramGb: (json['ram_gb'] as num).toDouble(),
      apiUsagePercent: (json['api_usage_percent'] as num).toDouble(),
      activeObRuns: json['active_ob_runs'] as int,
      activeTradingRuns: json['active_trading_runs'] as int,
      warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
    );
  }
}
