import 'package:flutter/material.dart';

import '../core/storage/local_ui_preferences_store.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController({LocalUiPreferencesStore? preferencesStore})
    : _preferencesStore = preferencesStore ?? LocalUiPreferencesStore();

  final LocalUiPreferencesStore _preferencesStore;
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  Future<void> initialize() async {
    final preferences = await _preferencesStore.readAppPreferences();
    _themeMode = switch (preferences.themePreference) {
      AppThemePreference.dark => ThemeMode.dark,
      AppThemePreference.light => ThemeMode.light,
    };
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) {
      return;
    }
    _themeMode = value;
    final current = await _preferencesStore.readAppPreferences();
    await _preferencesStore.writeAppPreferences(
      current.copyWith(
        themePreference: value == ThemeMode.dark
            ? AppThemePreference.dark
            : AppThemePreference.light,
      ),
    );
    notifyListeners();
  }
}
