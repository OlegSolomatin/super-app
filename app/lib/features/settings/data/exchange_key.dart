/// Model for exchange API keys.
class ExchangeKey {
  final String id;
  final String exchange;
  final String label;
  final bool isActive;
  final String status; // untested, valid, invalid
  final String? errorMessage;
  final double? balance;
  final String? balanceUpdatedAt;
  final String? lastCheckedAt;
  final String createdAt;
  final String updatedAt;

  ExchangeKey({
    required this.id,
    required this.exchange,
    required this.label,
    required this.isActive,
    required this.status,
    this.errorMessage,
    this.balance,
    this.balanceUpdatedAt,
    this.lastCheckedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ExchangeKey.fromJson(Map<String, dynamic> json) => ExchangeKey(
        id: json['id'] as String,
        exchange: json['exchange'] as String,
        label: json['label'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? true,
        status: json['status'] as String? ?? 'untested',
        errorMessage: json['error_message'] as String?,
        balance: (json['balance'] as num?)?.toDouble(),
        balanceUpdatedAt: json['balance_updated_at'] as String?,
        lastCheckedAt: json['last_checked_at'] as String?,
        createdAt: json['created_at'] as String,
        updatedAt: json['updated_at'] as String,
      );

  /// Human-readable status label.
  String get statusLabel {
    switch (status) {
      case 'valid':
        return '✅ Валидный';
      case 'invalid':
        return '❌ Невалидный';
      default:
        return '⏳ Не проверен';
    }
  }
}
