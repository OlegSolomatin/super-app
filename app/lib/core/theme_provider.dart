import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/core/section_theme.dart';
import 'package:app/core/theme.dart';

enum ThemeModePreference {
  dark,
  system,
  light;
}

class ThemeProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  ThemeModePreference _mode = ThemeModePreference.system;
  SectionTheme _section = SectionTheme.home;

  ThemeProvider(this._prefs) {
    _loadFromPrefs();
  }

  ThemeModePreference get mode => _mode;
  SectionTheme get section => _section;

  ThemeData get theme {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return AppTheme.of(
      mode: themeMode,
      section: _section,
      platformBrightness: brightness,
    );
  }

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

  /// Переключает skin раздела. Вызывать при навигации между разделами.
  void setSection(SectionTheme section) {
    if (_section != section) {
      _section = section;
      notifyListeners();
    }
  }

  void _loadFromPrefs() {
    final saved = _prefs.getString('theme_mode');
    if (saved != null) {
      _mode = ThemeModePreference.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => ThemeModePreference.system,
      );
    }
  }
}
