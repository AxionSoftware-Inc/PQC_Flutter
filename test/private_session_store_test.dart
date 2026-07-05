import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';
import 'package:pqc_chat_app/features/crypto/private_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('legacy session without chain keys is discarded on read', () async {
    SharedPreferences.setMockInitialValues({
      'local_secret_store_managed_keys': ['private_session_2_bob-device'],
    });
    final secretStore = _MemorySecretStore()
      ..values['private_session_2_bob-device'] = jsonEncode({
        'conversation_id': 2,
        'peer_device_id': 'bob-device',
        'peer_identity_public_key': 'peer-key',
        'root_key': base64Encode(List<int>.filled(32, 1)),
        'next_local_counter': 3,
        'established_by': 'session:v1',
      });
    final store = PrivateSessionStore(secretStore: secretStore);

    final session = await store.readSession(
      conversationId: 2,
      peerDeviceId: 'bob-device',
    );

    expect(session, isNull);
    expect(
      secretStore.values.containsKey('private_session_2_bob-device'),
      isFalse,
    );
  });
}

class _MemorySecretStore extends LocalSecretStore {
  _MemorySecretStore() : super();

  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
