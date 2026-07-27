import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorageUnavailableException implements Exception {
  const SecureStorageUnavailableException(this.operation, this.cause);

  final String operation;
  final Object cause;

  @override
  String toString() =>
      'Secure storage is unavailable during $operation. Refusing insecure fallback.';
}

class LocalSecretStore {
  static const _managedKeysRegistry = 'local_secret_store_managed_keys';
  static const _fallbackMasterKey = 'local_secret_store_fallback_master_key';
  static const _fallbackPrefix = 'local_secret:v1';
  static final _random = Random.secure();

  LocalSecretStore({
    FlutterSecureStorage? secureStorage,
    AesGcm? cipher,
    bool allowInsecureFallbackForTesting = false,
  }) : _secureStorage =
           secureStorage ??
           // Never wipe the keystore automatically after a transient platform
           // error. A reset here destroys historical chat keys and makes old
           // ciphertext fail authentication after relogin. Recovery must be
           // explicit and account-scoped instead.
           const FlutterSecureStorage(
             aOptions: AndroidOptions(resetOnError: false),
           ),
       _cipher = cipher ?? AesGcm.with256bits(),
       _allowInsecureFallbackForTesting =
           allowInsecureFallbackForTesting && !kReleaseMode;

  final FlutterSecureStorage _secureStorage;
  final AesGcm _cipher;
  final bool _allowInsecureFallbackForTesting;

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
    final wroteToSecureStorage = await _writeSecureValue(
      key: key,
      value: value,
    );
    await _registerManagedKey(key);

    if (_shouldMigrateLegacyAndroidSharedPrefs && wroteToSecureStorage) {
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

  Future<List<String>> listManagedKeys() {
    return _readManagedKeys();
  }

  Future<String?> _migrateLegacyAndroidValueIfNeeded(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final legacyValue = preferences.getString(key);
    if (legacyValue == null || legacyValue.isEmpty) {
      return null;
    }

    final clearValue = await _readFallbackValue(key);
    if (clearValue == null || clearValue.isEmpty) {
      throw const FormatException('Legacy secret storage entry is corrupted.');
    }
    final migrated = await _writeSecureValue(key: key, value: clearValue);
    if (!migrated) return clearValue;
    await preferences.remove(key);
    await _removeFallbackMasterKeyIfUnused(preferences);
    await _registerManagedKey(key);
    return clearValue;
  }

  Future<void> _removeFallbackMasterKeyIfUnused(
    SharedPreferences preferences,
  ) async {
    final managedKeys =
        preferences.getStringList(_managedKeysRegistry) ?? const <String>[];
    final hasFallbackEntries = managedKeys.any(
      (managedKey) =>
          preferences.getString(managedKey)?.startsWith('$_fallbackPrefix:') ??
          false,
    );
    if (!hasFallbackEntries) {
      await preferences.remove(_fallbackMasterKey);
    }
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
    } on MissingPluginException catch (error) {
      if (_allowInsecureFallbackForTesting) return _readFallbackValue(key);
      throw SecureStorageUnavailableException('read', error);
    } on PlatformException catch (error) {
      if (_allowInsecureFallbackForTesting) return _readFallbackValue(key);
      throw SecureStorageUnavailableException('read', error);
    }
  }

  Future<bool> _writeSecureValue({
    required String key,
    required String value,
  }) async {
    try {
      await _secureStorage.write(key: key, value: value);
      return true;
    } on MissingPluginException catch (error) {
      if (_allowInsecureFallbackForTesting) {
        await _writeFallbackValue(key: key, value: value);
        return false;
      }
      throw SecureStorageUnavailableException('write', error);
    } on PlatformException catch (error) {
      if (_allowInsecureFallbackForTesting) {
        await _writeFallbackValue(key: key, value: value);
        return false;
      }
      throw SecureStorageUnavailableException('write', error);
    }
  }

  Future<void> _deleteSecureValue(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } on MissingPluginException catch (error) {
      if (_allowInsecureFallbackForTesting) {
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove(key);
        return;
      }
      throw SecureStorageUnavailableException('delete', error);
    } on PlatformException catch (error) {
      if (_allowInsecureFallbackForTesting) {
        final preferences = await SharedPreferences.getInstance();
        await preferences.remove(key);
        return;
      }
      throw SecureStorageUnavailableException('delete', error);
    }
  }

  Future<String?> _readFallbackValue(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = _readSharedPreferencesValue(preferences, key);
    if (stored == null || stored.isEmpty) {
      return null;
    }
    if (!stored.startsWith('$_fallbackPrefix:')) {
      await _writeFallbackValue(key: key, value: stored);
      return stored;
    }

    final parts = stored.substring(_fallbackPrefix.length + 1).split(':');
    if (parts.length != 3) {
      return null;
    }
    try {
      final nonce = base64Decode(parts[0]);
      final cipherText = base64Decode(parts[1]);
      final mac = base64Decode(parts[2]);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
      final secretKey = await _fallbackSecretKey();
      final clearBytes = await _cipher.decrypt(secretBox, secretKey: secretKey);
      return utf8.decode(clearBytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeFallbackValue({
    required String key,
    required String value,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _cipher.encrypt(
      utf8.encode(value),
      secretKey: await _fallbackSecretKey(),
      nonce: nonce,
    );
    await preferences.setString(
      key,
      [
        _fallbackPrefix,
        base64Encode(secretBox.nonce),
        base64Encode(secretBox.cipherText),
        base64Encode(secretBox.mac.bytes),
      ].join(':'),
    );
  }

  Future<SecretKey> _fallbackSecretKey() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_fallbackMasterKey);
    if (existing != null && existing.isNotEmpty) {
      return SecretKey(base64Decode(existing));
    }

    final keyBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    await preferences.setString(_fallbackMasterKey, base64Encode(keyBytes));
    return SecretKey(keyBytes);
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
}
