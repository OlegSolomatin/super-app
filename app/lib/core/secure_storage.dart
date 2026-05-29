import 'package:shared_preferences/shared_preferences.dart';

class SecureStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  late final SharedPreferences _prefs;
  bool _initialized = false;

  /// Wait for SharedPreferences to be ready
  Future<void> get ready async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  Future<void> saveAccessToken(String token) async {
    await ready;
    await _prefs.setString(_accessTokenKey, token);
  }

  Future<void> saveRefreshToken(String token) async {
    await ready;
    await _prefs.setString(_refreshTokenKey, token);
  }

  Future<String?> getAccessToken() async {
    await ready;
    return _prefs.getString(_accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    await ready;
    return _prefs.getString(_refreshTokenKey);
  }

  Future<void> clearTokens() async {
    await ready;
    await _prefs.remove(_accessTokenKey);
    await _prefs.remove(_refreshTokenKey);
  }
}
