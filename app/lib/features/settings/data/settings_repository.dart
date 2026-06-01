import 'package:dio/dio.dart';

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
}
