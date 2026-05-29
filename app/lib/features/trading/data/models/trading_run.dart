class TradingRun {
  final String id;
  final String status;
  final String mode;
  final Map<String, dynamic> config;
  final String? strategyName;
  final double? startingBalance;
  final double? finalBalance;
  final int? totalTrades;
  final double? successRate;
  final double? pnl;
  final DateTime? createdAt;
  final DateTime? endsAt;
  final int? durationDays;

  const TradingRun({
    required this.id,
    required this.status,
    required this.mode,
    required this.config,
    this.strategyName,
    this.startingBalance,
    this.finalBalance,
    this.totalTrades,
    this.successRate,
    this.pnl,
    this.createdAt,
    this.endsAt,
    this.durationDays,
  });

  factory TradingRun.fromJson(Map<String, dynamic> json) {
    // Config is nested in the API response
    final cfg = (json['config'] as Map<String, dynamic>?) ?? {};
    // Result is nested (if present)
    final res = (json['result'] as Map<String, dynamic>?);
    return TradingRun(
      id: json['id'].toString(),
      status: json['status'] as String? ?? 'unknown',
      mode: json['mode'] as String? ?? 'history',
      config: cfg,
      strategyName: cfg['strategy'] as String?,
      startingBalance: (cfg['virtual_balance'] as num?)?.toDouble(),
      finalBalance: res != null ? (res['final_balance'] as num?)?.toDouble() : null,
      totalTrades: res != null ? res['total_trades'] as int? : null,
      successRate: res != null ? (res['win_rate'] as num?)?.toDouble() : null,
      pnl: res != null ? (res['profit_loss'] as num?)?.toDouble() : null,
      createdAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      endsAt: json['finished_at'] != null
          ? DateTime.parse(json['finished_at'] as String)
          : null,
      durationDays: cfg['duration_days'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'mode': mode,
        'config': config,
        'strategy_name': strategyName,
        'starting_balance': startingBalance,
        'final_balance': finalBalance,
        'total_trades': totalTrades,
        'success_rate': successRate,
        'pnl': pnl,
      };

  bool get isActive => status == 'running' || status == 'pending';

  /// Progress 0–100% for live virtual runs
  double? get progressPercent {
    if (createdAt == null || durationDays == null || durationDays == 0) return null;
    if (status != 'running') return 100.0;
    final elapsed = DateTime.now().difference(createdAt!).inSeconds;
    final total = durationDays! * 86400;
    return (elapsed / total * 100).clamp(0.0, 100.0);
  }

  /// Human-readable time remaining
  String? get timeRemainingLabel {
    if (createdAt == null || durationDays == null || durationDays == 0) return null;
    if (status != 'running') return null;
    final elapsed = DateTime.now().difference(createdAt!).inSeconds;
    final total = durationDays! * 86400;
    final remaining = total - elapsed;
    if (remaining <= 0) return 'Завершается…';
    final hours = remaining ~/ 3600;
    final minutes = (remaining % 3600) ~/ 60;
    if (hours > 24) return '${hours ~/ 24}д ${hours % 24}ч';
    return '${hours}ч ${minutes}м';
  }

  String get statusLabel {
    switch (status) {
      case 'running':
        return 'Запущен';
      case 'pending':
        return 'Ожидание';
      case 'done':
        return 'Завершён';
      case 'stopped':
        return 'Остановлен';
      case 'error':
        return 'Ошибка';
      default:
        return status;
    }
  }
}
