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
    return TradingRun(
      id: json['id'] as String,
      status: json['status'] as String,
      mode: json['mode'] as String,
      config: (json['config'] as Map<String, dynamic>?) ?? {},
      strategyName: json['strategy_name'] as String?,
      startingBalance: (json['starting_balance'] as num?)?.toDouble(),
      finalBalance: (json['final_balance'] as num?)?.toDouble(),
      totalTrades: json['total_trades'] as int?,
      successRate: (json['success_rate'] as num?)?.toDouble(),
      pnl: (json['pnl'] as num?)?.toDouble(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      endsAt: json['ends_at'] != null
          ? DateTime.parse(json['ends_at'] as String)
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
