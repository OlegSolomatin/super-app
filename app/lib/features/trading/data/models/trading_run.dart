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

  /// True if this is a pair-scanner strategy (all_pairs_hammer etc.)
  bool get isScanner {
    final strategy = config['strategy'] as String? ?? '';
    return strategy == 'all_pairs_hammer' || strategy == 'all_pairs_inverse_hammer';
  }

  /// True if this is virtual/real mode with duration
  bool get isVirtual {
    return mode == 'virtual' && durationDays != null && durationDays! > 0;
  }

  /// Estimated time label for fast history-mode runs (non-scanner)
  String? get estimatedTimeLabel {
    if (isScanner || isVirtual || status != 'running') return null;
    // History mode — fast, ~7 seconds
    return '~7 сек';
  }

  /// Human-readable pair name from config
  String get pairDisplay => (config['pair'] as String?) ?? '—';

  /// Base coin extracted from pair symbol (e.g. BTC from BTCUSDT)
  String get baseCoin {
    final pair = config['pair'] as String? ?? '';
    return pair.replaceAll('USDT', '').replaceAll('BUSD', '');
  }

  /// Icon URL for the pair
  String? get coinIconUrl {
    final base = baseCoin.toLowerCase();
    const iconMap = {
      'btc': 'bitcoin-btc', 'eth': 'ethereum-eth', 'bnb': 'binance-coin-bnb',
      'sol': 'solana-sol', 'xrp': 'xrp-xrp', 'ada': 'cardano-ada',
      'doge': 'dogecoin-doge', 'avax': 'avalanche-avax', 'dot': 'polkadot-dot',
      'matic': 'polygon-matic', 'ltc': 'litecoin-ltc', 'link': 'chainlink-link',
      'uni': 'uniswap-uni', 'atom': 'cosmos-atom', 'etc': 'ethereum-classic-etc',
      'fil': 'filecoin-fil', 'trx': 'tron-trx', 'xlm': 'stellar-xlm',
      'vet': 'vechain-vet', 'algo': 'algorand-algo', 'near': 'near-protocol-near',
      'ftm': 'fantom-ftm', 'sand': 'the-sandbox-sand', 'mana': 'decentraland-mana',
      'axs': 'axie-infinity-axs', 'ape': 'apecoin-ape', 'shib': 'shiba-inu-shib',
      'cro': 'crypto-com-cro', 'eos': 'eos-eos', 'icx': 'icon-icx',
      'zec': 'zcash-zec', 'xmr': 'monero-xmr', 'dash': 'dash-dash',
      'zil': 'zilliqa-zil', 'ksm': 'kusama-ksm', 'comp': 'compound-comp',
      'yfi': 'yearn-finance-yfi', 'aave': 'aave-aave', 'mkr': 'maker-mkr',
      'bat': 'basic-attention-token-bat', 'enj': 'enjin-coin-enj',
      'chz': 'chiliz-chz', 'one': 'harmony-one', 'ankr': 'ankr-ankr',
      'iost': 'iost-iost', 'waves': 'waves-waves', 'ont': 'ontology-ont',
      'iota': 'miota-iota', 'nano': 'nano-nano', 'lsk': 'lisk-lsk',
    };
    final name = iconMap[base];
    return name != null
        ? 'https://cryptologos.cc/logos/$name-logo.png?v=040'
        : null;
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
