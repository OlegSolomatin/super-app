class DeepseekBalanceInfo {
  final String currency;
  final double totalBalance;
  final double grantedBalance;
  final double toppedUpBalance;

  const DeepseekBalanceInfo({
    required this.currency,
    required this.totalBalance,
    required this.grantedBalance,
    required this.toppedUpBalance,
  });

  factory DeepseekBalanceInfo.fromJson(Map<String, dynamic> json) {
    return DeepseekBalanceInfo(
      currency: json['currency'] as String? ?? 'USD',
      totalBalance: double.tryParse(json['total_balance']?.toString() ?? '0') ?? 0,
      grantedBalance: double.tryParse(json['granted_balance']?.toString() ?? '0') ?? 0,
      toppedUpBalance: double.tryParse(json['topped_up_balance']?.toString() ?? '0') ?? 0,
    );
  }
}

class DeepseekBalance {
  final bool isAvailable;
  final List<DeepseekBalanceInfo> balanceInfos;

  const DeepseekBalance({
    required this.isAvailable,
    required this.balanceInfos,
  });

  factory DeepseekBalance.fromJson(Map<String, dynamic> json) {
    return DeepseekBalance(
      isAvailable: json['is_available'] as bool? ?? false,
      balanceInfos: (json['balance_infos'] as List?)
              ?.map((e) => DeepseekBalanceInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
