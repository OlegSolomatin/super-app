import 'package:dio/dio.dart';
import 'package:app/models/user.dart';

class UserRepository {
  final Dio _dio;

  UserRepository(this._dio);

  Future<User> getMe() async {
    final response = await _dio.get('/users/me');
    return User.fromJson(response.data);
  }
}
