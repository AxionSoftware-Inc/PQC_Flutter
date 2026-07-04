import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalSecretStore {
  LocalSecretStore({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
          );

  final FlutterSecureStorage _secureStorage;

  bool get _useSharedPreferencesOnThisPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<String?> read(String key) async {
    if (_useSharedPreferencesOnThisPlatform) {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(key);
    }
    return _secureStorage.read(key: key);
  }

  Future<void> write({required String key, required String value}) async {
    if (_useSharedPreferencesOnThisPlatform) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, value);
      return;
    }
    await _secureStorage.write(key: key, value: value);
  }

  Future<void> delete(String key) async {
    if (_useSharedPreferencesOnThisPlatform) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(key);
      return;
    }
    await _secureStorage.delete(key: key);
  }

  Future<void> deleteAll() async {
    if (_useSharedPreferencesOnThisPlatform) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.clear();
      return;
    }
    await _secureStorage.deleteAll();
  }
}
