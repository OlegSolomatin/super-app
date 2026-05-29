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
  });

  factory TradingRun.fromJson(Map<String, dynamic> json) {
    // Config is nested in the API response
    final cfg = (json['config'] as Map<String, dynamic>?) ?? {};
    return TradingRun(
      id: json['id'].toString(),
      status: json['status'] as String? ?? 'unknown',
      mode: json['mode'] as String? ?? 'history',
      config: cfg,
      strategyName: cfg['strategy'] as String?,
      startingBalance: (cfg['virtual_balance'] as num?)?.toDouble(),
      finalBalance: (json['final_balance'] as num?)?.toDouble(),
      totalTrades: json['total_trades'] as int?,
      successRate: (json['success_rate'] as num?)?.toDouble(),
      pnl: (json['profit_loss'] as num?)?.toDouble(),
      createdAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      endsAt: json['finished_at'] != null
          ? DateTime.parse(json['finished_at'] as String)
          : null,
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
