import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/local_secret_store.dart';

class OutboundMessageCache {
  OutboundMessageCache({LocalSecretStore? secretStore, Sha256? hashAlgorithm})
    : _secretStore = secretStore ?? LocalSecretStore(),
      _hashAlgorithm = hashAlgorithm ?? Sha256();

  final LocalSecretStore _secretStore;
  final Sha256 _hashAlgorithm;
  static const _registryKey = 'outbound_message_cache_registry';
  static const _maxEntries = 300;

  Future<void> storePlaintext({
    required String payload,
    required String plaintext,
  }) async {
    final storageKey = await _storageKey(payload);
    await _secretStore.write(key: storageKey, value: plaintext);
    await _touchRegistry(storageKey);
  }

  Future<String?> readPlaintext(String payload) async {
    final storageKey = await _storageKey(payload);
    final plaintext = await _secretStore.read(storageKey);
    if (plaintext != null) {
      await _touchRegistry(storageKey);
    }
    return plaintext;
  }

  Future<void> deletePlaintext(String payload) async {
    final storageKey = await _storageKey(payload);
    await _secretStore.delete(storageKey);
    await _removeFromRegistry(storageKey);
  }

  Future<void> clearAll() async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getStringList(_registryKey) ?? const <String>[];
    for (final key in current) {
      await _secretStore.delete(key);
    }
    await preferences.remove(_registryKey);
  }

  Future<String> _storageKey(String payload) async {
    final digest = await _hashAlgorithm.hash(utf8.encode(payload));
    return 'outbound_message_${base64UrlEncode(digest.bytes)}';
  }

  Future<void> _touchRegistry(String storageKey) async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getStringList(_registryKey) ?? <String>[];
    final next = [...current.where((item) => item != storageKey), storageKey];
    while (next.length > _maxEntries) {
      final removedKey = next.removeAt(0);
      await _secretStore.delete(removedKey);
    }
    await preferences.setStringList(_registryKey, next);
  }

  Future<void> _removeFromRegistry(String storageKey) async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getStringList(_registryKey) ?? <String>[];
    if (!current.contains(storageKey)) {
      return;
    }
    final next = [...current]..remove(storageKey);
    if (next.isEmpty) {
      await preferences.remove(_registryKey);
      return;
    }
    await preferences.setStringList(_registryKey, next);
  }
}
