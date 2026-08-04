import 'package:flutter/material.dart';

import 'app_localization.dart';
import '../core/storage/local_ui_preferences_store.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController({LocalUiPreferencesStore? preferencesStore})
    : _preferencesStore = preferencesStore ?? LocalUiPreferencesStore();

  final LocalUiPreferencesStore _preferencesStore;
  ThemeMode _themeMode = ThemeMode.light;
  AppLanguagePreference _languagePreference = AppLanguagePreference.uzbek;

  ThemeMode get themeMode => _themeMode;
  AppLanguagePreference get languagePreference => _languagePreference;
  Locale get locale => Locale(
    _languagePreference == AppLanguagePreference.english ? 'en' : 'uz',
  );

  Future<void> initialize() async {
    final preferences = await _preferencesStore.readAppPreferences();
    _themeMode = switch (preferences.themePreference) {
      AppThemePreference.dark => ThemeMode.dark,
      AppThemePreference.light => ThemeMode.light,
    };
    _languagePreference = preferences.languagePreference;
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

  Future<void> setLanguage(AppLanguagePreference value) async {
    if (_languagePreference == value) {
      return;
    }
    _languagePreference = value;
    final current = await _preferencesStore.readAppPreferences();
    await _preferencesStore.writeAppPreferences(
      current.copyWith(languagePreference: value),
    );
    notifyListeners();
  }
}
