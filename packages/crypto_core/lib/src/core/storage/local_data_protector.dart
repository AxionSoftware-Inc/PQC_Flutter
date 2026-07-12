import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'local_secret_store.dart';

class LocalDataProtector {
  LocalDataProtector({LocalSecretStore? secretStore, AesGcm? cipher})
    : _secretStore = secretStore ?? LocalSecretStore(),
      _cipher = cipher ?? AesGcm.with256bits();

  static const _keyStorageKey = 'local_data_protection_key';
  static const _prefix = 'local-data:v1';
  static final _random = Random.secure();

  final LocalSecretStore _secretStore;
  final AesGcm _cipher;
  SecretKey? _cachedKey;

  Future<String> protect(String value) async {
    if (value.isEmpty || value == '[decrypt-error]') {
      return value;
    }
    if (value.startsWith('$_prefix:')) {
      return value;
    }
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _cipher.encrypt(
      utf8.encode(value),
      secretKey: await _secretKey(),
      nonce: nonce,
    );
    return [
      _prefix,
      base64Encode(secretBox.nonce),
      base64Encode(secretBox.cipherText),
      base64Encode(secretBox.mac.bytes),
    ].join(':');
  }

  Future<String> unprotect(String value) async {
    if (value.isEmpty || value == '[decrypt-error]') {
      return value;
    }
    if (!value.startsWith('$_prefix:')) {
      return value;
    }
    final parts = value.substring(_prefix.length + 1).split(':');
    if (parts.length != 3) {
      return '';
    }
    try {
      final secretBox = SecretBox(
        base64Decode(parts[1]),
        nonce: base64Decode(parts[0]),
        mac: Mac(base64Decode(parts[2])),
      );
      final clearBytes = await _cipher.decrypt(
        secretBox,
        secretKey: await _secretKey(),
      );
      return utf8.decode(clearBytes);
    } catch (_) {
      return '';
    }
  }

  Future<SecretKey> _secretKey() async {
    final cachedKey = _cachedKey;
    if (cachedKey != null) {
      return cachedKey;
    }
    final existing = await _secretStore.read(_keyStorageKey);
    if (existing != null && existing.isNotEmpty) {
      final secretKey = SecretKey(base64Decode(existing));
      _cachedKey = secretKey;
      return secretKey;
    }
    final keyBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    await _secretStore.write(key: _keyStorageKey, value: base64Encode(keyBytes));
    final secretKey = SecretKey(keyBytes);
    _cachedKey = secretKey;
    return secretKey;
  }
}
