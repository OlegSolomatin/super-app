import 'package:dio/dio.dart';
import 'package:app/features/settings/data/exchange_key.dart';

class TelegramBotData {
  final String id;
  final String name;
  final String botToken;
  final String chatId;
  final String? createdAt;

  TelegramBotData({
    required this.id,
    required this.name,
    required this.botToken,
    required this.chatId,
    this.createdAt,
  });

  factory TelegramBotData.fromJson(Map<String, dynamic> json) => TelegramBotData(
    id: json['id'] as String,
    name: json['name'] as String,
    botToken: json['bot_token'] as String,
    chatId: json['chat_id'] as String,
    createdAt: json['created_at'] as String?,
  );
}

class SettingsRepository {
  final Dio _dio;
  SettingsRepository(this._dio);

  Future<List<TelegramBotData>> getBots() async {
    final resp = await _dio.get('/settings/telegram-bots');
    return (resp.data as List).map((e) => TelegramBotData.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<TelegramBotData> createBot({
    required String name,
    required String botToken,
    required String chatId,
  }) async {
    final resp = await _dio.post('/settings/telegram-bots', data: {
      'name': name,
      'bot_token': botToken,
      'chat_id': chatId,
    });
    return TelegramBotData.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteBot(String id) async {
    await _dio.delete('/settings/telegram-bots/$id');
  }

  // ── Exchange API Keys ─────────────────────────────────────────────

  /// List all exchange API keys for the current user.
  Future<List<ExchangeKey>> getExchangeKeys() async {
    final resp = await _dio.get('/exchange-keys');
    final data = resp.data as Map<String, dynamic>;
    return (data['items'] as List)
        .map((e) => ExchangeKey.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Add a new exchange API key.
  Future<ExchangeKey> createExchangeKey({
    required String exchange,
    required String label,
    required String apiKey,
    required String apiSecret,
    String? passphrase,
  }) async {
    final resp = await _dio.post('/exchange-keys', data: {
      'exchange': exchange,
      'label': label,
      'api_key': apiKey,
      'api_secret': apiSecret,
      if (passphrase != null && passphrase.isNotEmpty) 'passphrase': passphrase,
    });
    return ExchangeKey.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Update an exchange API key.
  Future<ExchangeKey> updateExchangeKey({
    required String id,
    String? label,
    String? apiKey,
    String? apiSecret,
    bool? isActive,
  }) async {
    final data = <String, dynamic>{};
    if (label != null) data['label'] = label;
    if (apiKey != null) data['api_key'] = apiKey;
    if (apiSecret != null) data['api_secret'] = apiSecret;
    if (isActive != null) data['is_active'] = isActive;

    final resp = await _dio.put('/exchange-keys/$id', data: data);
    return ExchangeKey.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Delete an exchange API key.
  Future<void> deleteExchangeKey(String id) async {
    await _dio.delete('/exchange-keys/$id');
  }

  /// Test/check an exchange API key.
  Future<ExchangeKey> checkExchangeKey(String id) async {
    final resp = await _dio.post('/exchange-keys/$id/check');
    return ExchangeKey.fromJson(resp.data as Map<String, dynamic>);
  }
}
