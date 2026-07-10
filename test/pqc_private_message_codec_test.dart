import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_identity_service.dart';
import 'package:pqc_chat_app/core/device/device_pqc_key_service.dart';
import 'package:pqc_chat_app/core/device/device_pqc_signing_key_service.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'package:pqc_chat_app/core/models/conversation.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';
import 'package:pqc_chat_app/features/crypto/message_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('pqc private chat encrypts and decrypts between two devices', () async {
    final aliceSecrets = _MemorySecretStore();
    final bobSecrets = _MemorySecretStore();
    final alicePqc = DevicePqcKeyService(secretStore: aliceSecrets);
    final bobPqc = DevicePqcKeyService(secretStore: bobSecrets);
    final aliceSigning = DevicePqcSigningKeyService(secretStore: aliceSecrets);
    final bobSigning = DevicePqcSigningKeyService(secretStore: bobSecrets);

    final alicePqcMaterial = await alicePqc.getOrCreateKeyMaterial();
    final bobPqcMaterial = await bobPqc.getOrCreateKeyMaterial();
    final aliceSigningMaterial = await aliceSigning.getOrCreateKeyMaterial();
    final bobSigningMaterial = await bobSigning.getOrCreateKeyMaterial();

    final conversation = Conversation(
      id: 2,
      type: 'private',
      title: '',
      participantIds: const [1, 2],
      lastMessagePreview: '',
      updatedAt: DateTime.parse('2026-07-10T00:00:00Z'),
    );
    final usersById = {
      1: AppUser(
        id: 1,
        username: 'alice',
        displayName: 'Alice',
        devices: [
          AppUserDevice(
            deviceId: 'alice-device',
            deviceName: 'Alice Mac',
            platform: 'macos',
            identityPublicKey: '',
            keyAlgorithm: '',
            pqcPublicKey: alicePqcMaterial.publicKey,
            pqcAlgorithm: alicePqcMaterial.algorithm,
            pqcSigningPublicKey: aliceSigningMaterial.publicKey,
            pqcSigningAlgorithm: aliceSigningMaterial.algorithm,
          ),
        ],
      ),
      2: AppUser(
        id: 2,
        username: 'bob',
        displayName: 'Bob',
        devices: [
          AppUserDevice(
            deviceId: 'bob-device',
            deviceName: 'Bob Android',
            platform: 'android',
            identityPublicKey: '',
            keyAlgorithm: '',
            pqcPublicKey: bobPqcMaterial.publicKey,
            pqcAlgorithm: bobPqcMaterial.algorithm,
            pqcSigningPublicKey: bobSigningMaterial.publicKey,
            pqcSigningAlgorithm: bobSigningMaterial.algorithm,
          ),
        ],
      ),
    };

    final aliceCodec = PqcPrivateMessageCodec(
      deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
      devicePqcKeyService: alicePqc,
      devicePqcSigningKeyService: aliceSigning,
    );
    final bobCodec = PqcPrivateMessageCodec(
      deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
      devicePqcKeyService: bobPqc,
      devicePqcSigningKeyService: bobSigning,
    );

    final payload = await aliceCodec.encrypt(
      currentUserId: 1,
      conversation: conversation,
      plaintext: 'salom pqc',
      usersById: usersById,
    );
    final decryptedByBob = await bobCodec.decrypt(
      currentUserId: 2,
      conversation: conversation,
      payload: payload,
      usersById: usersById,
    );
    final decryptedByAlice = await aliceCodec.decrypt(
      currentUserId: 1,
      conversation: conversation,
      payload: payload,
      usersById: usersById,
    );

    expect(payload, startsWith('pqc:v1:'));
    expect(payload.contains('salom pqc'), isFalse);
    expect(decryptedByBob, 'salom pqc');
    expect(decryptedByAlice, 'salom pqc');
  });
}

class _FakeDeviceIdentityService extends DeviceIdentityService {
  _FakeDeviceIdentityService(this.deviceId);

  final String deviceId;

  @override
  Future<DeviceIdentity> getIdentity() async {
    return DeviceIdentity(
      id: deviceId,
      deviceName: 'test-$deviceId',
      platform: 'test',
    );
  }
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
