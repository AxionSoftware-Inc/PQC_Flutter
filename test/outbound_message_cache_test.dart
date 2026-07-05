import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';
import 'package:pqc_chat_app/features/crypto/outbound_message_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('outbound cache clearAll removes stored plaintext entries', () async {
    SharedPreferences.setMockInitialValues({});
    final secretStore = _MemorySecretStore();
    final cache = OutboundMessageCache(secretStore: secretStore);

    await cache.storePlaintext(payload: 'a', plaintext: 'alpha');
    await cache.storePlaintext(payload: 'b', plaintext: 'beta');
    expect(secretStore.values.length, 2);

    await cache.clearAll();

    expect(secretStore.values, isEmpty);
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
