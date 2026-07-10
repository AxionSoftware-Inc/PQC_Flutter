import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_key_service.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';

void main() {
  test(
    'device key service restores the exact x25519 keypair from storage',
    () async {
      final secretStore = _MemorySecretStore();
      final service = DeviceKeyService(secretStore: secretStore);

      final firstMaterial = await service.getOrCreateKeyMaterial();
      final restoredPair = await service.getIdentityKeyPair();
      final restoredData = await restoredPair.extract();

      expect(
        restoredData.publicKey.bytes,
        base64Decode(firstMaterial.publicKey),
      );
    },
  );
}

class _MemorySecretStore extends LocalSecretStore {
  _MemorySecretStore() : super();

  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
