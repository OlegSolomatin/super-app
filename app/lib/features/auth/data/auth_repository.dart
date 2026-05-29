import 'package:dio/dio.dart';
import 'package:app/models/auth_tokens.dart';

class AuthRepository {
  final Dio _dio;

  AuthRepository(this._dio);

  Future<AuthTokens> register({
    required String email,
    required String password,
    required String username,
  }) async {
    final response = await _dio.post(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        'username': username,
      },
    );

    return AuthTokens.fromJson(response.data);
  }

  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      '/auth/login',
      data: {
        'email': email,
        'password': password,
      },
    );

    return AuthTokens.fromJson(response.data);
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final response = await _dio.post(
      '/auth/refresh',
      data: {
        'refresh_token': refreshToken,
      },
    );

    return AuthTokens.fromJson(response.data);
  }
}
