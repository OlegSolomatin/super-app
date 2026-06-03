import 'package:flutter/material.dart';
import 'package:app/models/user.dart';

/// Глобальное состояние текущего пользователя.
/// Устанавливается после логина или при загрузке HomePage.
class UserProvider extends ChangeNotifier {
  User? _user;

  User? get user => _user;

  bool get isLoggedIn => _user != null;

  bool get isAdmin => _user?.roles?.contains('admin') ?? false;

  String get username => _user?.username ?? 'Пользователь';

  String get initials => _user?.username != null
      ? _user!.username[0].toUpperCase()
      : '?';

  void setUser(User? user) {
    _user = user;
    notifyListeners();
  }

  void clear() {
    _user = null;
    notifyListeners();
  }
}
