import 'package:dio/dio.dart';
import 'secure_storage.dart';

class DioClient {
  static const String baseUrl = '/api/v1';

  late final Dio dio;
  final SecureStorage _storage;
  final void Function()? _onAuthFailure;

  DioClient(this._storage, {void Function()? onAuthFailure})
      : _onAuthFailure = onAuthFailure {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Skip auth for login/register/refresh endpoints
          if (options.path.contains('/auth/')) {
            return handler.next(options);
          }

          final token = await _storage.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            // Try to refresh the token
            final refreshToken = await _storage.getRefreshToken();
            if (refreshToken != null) {
              try {
                final response = await dio.post(
                  '/auth/refresh',
                  data: {'refresh_token': refreshToken},
                );

                if (response.statusCode == 200) {
                  final newAccessToken = response.data['access_token'];
                  final newRefreshToken = response.data['refresh_token'];

                  await _storage.saveAccessToken(newAccessToken);
                  await _storage.saveRefreshToken(newRefreshToken);

                  // Retry the original request
                  error.requestOptions.headers['Authorization'] =
                      'Bearer $newAccessToken';
                  final retryResponse = await dio.fetch(error.requestOptions);
                  return handler.resolve(retryResponse);
                }
              } catch (_) {
                // Refresh failed, clear tokens
                await _storage.clearTokens();
                _onAuthFailure?.call();
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }
}
