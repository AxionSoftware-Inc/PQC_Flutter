import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'v3 self message survives recovery onto a fresh installation id',
    () async {
      final oldStore = _MemorySecretStore();
      final oldIdentity = _FixedIdentityService('bob-installation-old');
      final oldPqc = DevicePqcKeyService(secretStore: oldStore);
      final oldSigning = DevicePqcSigningKeyService(secretStore: oldStore);
      final oldRegistry = KeyMaterialRegistry(
        deviceIdentityService: oldIdentity,
        deviceKeyService: DeviceKeyService(secretStore: oldStore),
        devicePqcKeyService: oldPqc,
        devicePqcSigningKeyService: oldSigning,
        secretStore: oldStore,
      );
      final oldKeyset = await oldRegistry.ensureCurrentKeysetRegistered();
      final oldWriter = V3ChatCipherAlgorithm(
        identityService: oldIdentity,
        pqcKeyService: oldPqc,
        signingKeyService: oldSigning,
        keyMaterialRegistry: oldRegistry,
      );
      final conversation = Conversation(
        id: 91,
        type: 'private',
        title: '',
        participantIds: const [2],
        lastMessagePreview: '',
        updatedAt: DateTime.utc(2026, 7, 18),
      );
      final payload = await oldWriter.encrypt(
        context: ChatCryptoContext(
          currentUserId: 2,
          conversation: conversation,
          usersById: {
            2: AppUser(
              id: 2,
              username: 'bob',
              displayName: 'Bob',
              devices: [
                AppUserDevice(
                  deviceId: oldKeyset.deviceId,
                  deviceName: 'Bob phone',
                  platform: 'android',
                  identityPublicKey: oldKeyset.identityPublicKey,
                  keyAlgorithm: oldKeyset.identityAlgorithm,
                  pqcPublicKey: oldKeyset.pqcPublicKey,
                  pqcAlgorithm: oldKeyset.pqcAlgorithm,
                  pqcSigningPublicKey: oldKeyset.pqcSigningPublicKey,
                  pqcSigningAlgorithm: oldKeyset.pqcSigningAlgorithm,
                ),
              ],
            ),
          },
          messageId: 'v3-self-message-1',
        ),
        plaintext: 'survives reinstall',
      );
      final manifest = await CryptoBackupService(
        keyMaterialRegistry: oldRegistry,
        secretStore: oldStore,
      ).exportEnterpriseRecoveryManifest();

      // This represents an app uninstall/reinstall: no local key material and
      // a new installation id, followed by automatic account recovery.
      final freshStore = _MemorySecretStore();
      final freshIdentity = _FixedIdentityService('bob-installation-fresh');
      final freshPqc = DevicePqcKeyService(secretStore: freshStore);
      final freshSigning = DevicePqcSigningKeyService(secretStore: freshStore);
      final freshRegistry = KeyMaterialRegistry(
        deviceIdentityService: freshIdentity,
        deviceKeyService: DeviceKeyService(secretStore: freshStore),
        devicePqcKeyService: freshPqc,
        devicePqcSigningKeyService: freshSigning,
        secretStore: freshStore,
      );
      await CryptoBackupService(
        keyMaterialRegistry: freshRegistry,
        secretStore: freshStore,
      ).importEnterpriseRecoveryManifest(manifest);
      final freshReader = V3ChatCipherAlgorithm(
        identityService: freshIdentity,
        pqcKeyService: freshPqc,
        signingKeyService: freshSigning,
        keyMaterialRegistry: freshRegistry,
      );

      final plaintext = await freshReader.decrypt(
        context: ChatCryptoContext(
          currentUserId: 2,
          conversation: conversation,
          usersById: const {},
          messageId: 'v3-self-message-1',
        ),
        payload: payload,
      );

      expect(plaintext, 'survives reinstall');
    },
  );
}

class _FixedIdentityService extends DeviceIdentityService {
  _FixedIdentityService(this.deviceId);

  final String deviceId;

  @override
  Future<DeviceIdentity> getIdentity() async => DeviceIdentity(
    id: deviceId,
    deviceName: 'test-$deviceId',
    platform: 'test',
  );
}

class _MemorySecretStore extends LocalSecretStore {
  final Map<String, String> _values = {};
  final Set<String> _managed = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
    _managed.add(key);
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
    _managed.remove(key);
  }

  @override
  Future<List<String>> listManagedKeys() async => _managed.toList();
}
