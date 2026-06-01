import 'package:dio/dio.dart';
import 'package:app/models/user.dart';

class UserRepository {
  final Dio _dio;

  UserRepository(this._dio);

  Future<User> getMe() async {
    final response = await _dio.get('/users/me');
    return User.fromJson(response.data);
  }

  Future<User> updateMe({
    String? username,
    String? bio,
    String? avatarUrl,
  }) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (bio != null) body['bio'] = bio;
    if (avatarUrl != null) body['avatar_url'] = avatarUrl;

    final response = await _dio.patch('/users/me', data: body);
    return User.fromJson(response.data);
  }
}
