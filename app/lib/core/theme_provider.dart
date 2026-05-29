import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeModePreference {
  dark,
  system,
  light;
}

class ThemeProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  ThemeModePreference _mode = ThemeModePreference.dark;

  ThemeProvider(this._prefs) {
    _loadFromPrefs();
  }

  ThemeModePreference get mode => _mode;

  ThemeMode get themeMode => switch (_mode) {
        ThemeModePreference.dark => ThemeMode.dark,
        ThemeModePreference.system => ThemeMode.system,
        ThemeModePreference.light => ThemeMode.light,
      };

  void setMode(ThemeModePreference mode) {
    _mode = mode;
    _prefs.setString('theme_mode', mode.name);
    notifyListeners();
  }

  void _loadFromPrefs() {
    final saved = _prefs.getString('theme_mode');
    if (saved != null) {
      _mode = ThemeModePreference.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => ThemeModePreference.dark,
      );
    }
  }
}
