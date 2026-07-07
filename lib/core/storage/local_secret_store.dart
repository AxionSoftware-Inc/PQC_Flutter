import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalSecretStore {
  static const _managedKeysRegistry = 'local_secret_store_managed_keys';

  LocalSecretStore({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
          );

  final FlutterSecureStorage _secureStorage;

  bool get _shouldMigrateLegacyAndroidSharedPrefs =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<String?> read(String key) async {
    final secureValue = await _readSecureValue(key);
    if (secureValue != null && secureValue.isNotEmpty) {
      return secureValue;
    }

    if (_shouldMigrateLegacyAndroidSharedPrefs) {
      return _migrateLegacyAndroidValueIfNeeded(key);
    }

    return secureValue;
  }

  Future<void> write({required String key, required String value}) async {
    await _writeSecureValue(key: key, value: value);
    await _registerManagedKey(key);

    if (_shouldMigrateLegacyAndroidSharedPrefs) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(key);
    }
  }

  Future<void> delete(String key) async {
    await _deleteSecureValue(key);
    await _unregisterManagedKey(key);

    if (_shouldMigrateLegacyAndroidSharedPrefs) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(key);
    }
  }

  Future<void> deleteAll() async {
    final managedKeys = await _readManagedKeys();
    for (final key in managedKeys) {
      await _deleteSecureValue(key);
    }

    if (_shouldMigrateLegacyAndroidSharedPrefs) {
      final preferences = await SharedPreferences.getInstance();
      for (final key in managedKeys) {
        await preferences.remove(key);
      }
      await preferences.remove(_managedKeysRegistry);
      return;
    }

    await _clearManagedKeysRegistry();
  }

  Future<String?> _migrateLegacyAndroidValueIfNeeded(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final legacyValue = preferences.getString(key);
    if (legacyValue == null || legacyValue.isEmpty) {
      return null;
    }

    await _writeSecureValue(key: key, value: legacyValue);
    await preferences.remove(key);
    await _registerManagedKey(key);
    return legacyValue;
  }

  Future<void> _registerManagedKey(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final current =
        preferences.getStringList(_managedKeysRegistry) ?? <String>[];
    if (current.contains(key)) {
      return;
    }
    await preferences.setStringList(_managedKeysRegistry, [...current, key]);
  }

  Future<void> _unregisterManagedKey(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final current =
        preferences.getStringList(_managedKeysRegistry) ?? <String>[];
    if (!current.contains(key)) {
      return;
    }
    final next = [...current]..remove(key);
    if (next.isEmpty) {
      await preferences.remove(_managedKeysRegistry);
      return;
    }
    await preferences.setStringList(_managedKeysRegistry, next);
  }

  Future<List<String>> _readManagedKeys() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_managedKeysRegistry) ?? <String>[];
  }

  Future<void> _clearManagedKeysRegistry() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_managedKeysRegistry);
  }

  Future<String?> _readSecureValue(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } on MissingPluginException {
      final preferences = await SharedPreferences.getInstance();
      return _readSharedPreferencesValue(preferences, key);
    } on PlatformException {
      final preferences = await SharedPreferences.getInstance();
      return _readSharedPreferencesValue(preferences, key);
    }
  }

  String? _readSharedPreferencesValue(
    SharedPreferences preferences,
    String key,
  ) {
    final value = preferences.get(key);
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    if (value is int || value is double || value is bool) {
      return value.toString();
    }
    return null;
  }

  Future<void> _writeSecureValue({
    required String key,
    required String value,
  }) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } on MissingPluginException {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, value);
    } on PlatformException {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, value);
    }
  }

  Future<void> _deleteSecureValue(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } on MissingPluginException {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(key);
    } on PlatformException {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(key);
    }
  }
}
