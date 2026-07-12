import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/models/session_user.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';
import 'package:pqc_chat_app/core/storage/session_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'session storage keeps session in secret store and remembers identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secretStore = _MemorySecretStore();
      final storage = SessionStorage(secretStore: secretStore);
      const session = SessionUser(
        id: 7,
        username: 'riley',
        displayName: 'Riley',
        deviceId: 'device-1',
        token: 'secret-token',
      );

      await storage.write(session);

      final restored = await storage.read();
      final remembered = await storage.readRememberedIdentity();
      final historyOwner = await storage.readLocalHistoryOwner();
      final prefs = await SharedPreferences.getInstance();

      expect(restored?.token, 'secret-token');
      expect(secretStore.values['session_token'], 'secret-token');
      expect(prefs.getString('session_token'), isNull);
      expect(remembered?.displayName, 'Riley');
      expect(remembered?.username, 'riley');
      expect(historyOwner, isNull);
    },
  );

  test(
    'clear removes secret session but can keep remembered identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secretStore = _MemorySecretStore();
      final storage = SessionStorage(secretStore: secretStore);
      const session = SessionUser(
        id: 7,
        username: 'riley',
        displayName: 'Riley',
        deviceId: 'device-1',
        token: 'secret-token',
      );

      await storage.write(session);
      await storage.clear(clearRememberedIdentity: false);

      final restored = await storage.read();
      final remembered = await storage.readRememberedIdentity();

      expect(restored, isNull);
      expect(remembered?.displayName, 'Riley');
    },
  );

  test('local history owner can be written independently from session token', () async {
    SharedPreferences.setMockInitialValues({});
    final secretStore = _MemorySecretStore();
    final storage = SessionStorage(secretStore: secretStore);
    const session = SessionUser(
      id: 11,
      accountId: 42,
      username: 'sam',
      displayName: 'Sam',
      deviceId: 'device-42',
      token: 'temporary-token',
    );

    await storage.writeLocalHistoryOwner(session);
    await storage.clear(clearRememberedIdentity: false);

    final historyOwner = await storage.readLocalHistoryOwner();
    final remembered = await storage.readRememberedIdentity();

    expect(historyOwner?.accountId, 42);
    expect(historyOwner?.username, 'sam');
    expect(historyOwner?.displayName, 'Sam');
    expect(remembered, isNull);
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
