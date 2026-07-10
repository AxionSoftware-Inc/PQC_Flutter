import 'dart:convert';

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
    final fixture = await _buildFixture();

    final payload = await fixture.aliceCodec.encrypt(
      currentUserId: 1,
      conversation: fixture.conversation,
      plaintext: 'salom pqc',
      usersById: fixture.usersById,
    );
    final decryptedByBob = await fixture.bobCodec.decrypt(
      currentUserId: 2,
      conversation: fixture.conversation,
      payload: payload,
      usersById: fixture.usersById,
    );
    final decryptedByAlice = await fixture.aliceCodec.decrypt(
      currentUserId: 1,
      conversation: fixture.conversation,
      payload: payload,
      usersById: fixture.usersById,
    );

    expect(payload, startsWith('pqc:v1:'));
    expect(payload.contains('salom pqc'), isFalse);
    expect(decryptedByBob, 'salom pqc');
    expect(decryptedByAlice, 'salom pqc');
  });

  test(
    'pqc private payload contains real ml-kem and ml-dsa sized fields',
    () async {
      final fixture = await _buildFixture();
      final payload = await fixture.aliceCodec.encrypt(
        currentUserId: 1,
        conversation: fixture.conversation,
        plaintext: 'PQC payload metrics',
        usersById: fixture.usersById,
      );

      final parts = payload
          .substring(PqcPrivateMessageCodec.prefix.length + 1)
          .split(':');

      expect(parts, hasLength(15));
      expect(parts[0], 'alice-device');
      expect(parts[2], 'bob-device');
      expect(
        base64Decode(parts[1]).length,
        DevicePqcSigningKeyService.publicKeyLength,
      );
      expect(
        base64Decode(parts[3]).length,
        DevicePqcKeyService.ciphertextLength,
      );
      expect(
        base64Decode(parts[7]).length,
        DevicePqcKeyService.ciphertextLength,
      );
      expect(base64Decode(parts[4]).length, 12);
      expect(base64Decode(parts[8]).length, 12);
      expect(
        base64Decode(parts[5]).length,
        DevicePqcKeyService.sharedSecretLength,
      );
      expect(
        base64Decode(parts[9]).length,
        DevicePqcKeyService.sharedSecretLength,
      );
      expect(base64Decode(parts[6]).length, 16);
      expect(base64Decode(parts[10]).length, 16);
      expect(base64Decode(parts[11]).length, 12);
      expect(base64Decode(parts[12]).length, greaterThanOrEqualTo(19));
      expect(base64Decode(parts[13]).length, 16);
      expect(base64Decode(parts[14]).length, greaterThan(3000));
      expect(payload.length, greaterThan(9000));
      expect(payload.contains('PQC payload metrics'), isFalse);
    },
  );
}

Future<_Fixture> _buildFixture() async {
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

  return _Fixture(
    conversation: conversation,
    usersById: usersById,
    aliceCodec: PqcPrivateMessageCodec(
      deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
      devicePqcKeyService: alicePqc,
      devicePqcSigningKeyService: aliceSigning,
    ),
    bobCodec: PqcPrivateMessageCodec(
      deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
      devicePqcKeyService: bobPqc,
      devicePqcSigningKeyService: bobSigning,
    ),
  );
}

class _Fixture {
  const _Fixture({
    required this.conversation,
    required this.usersById,
    required this.aliceCodec,
    required this.bobCodec,
  });

  final Conversation conversation;
  final Map<int, AppUser> usersById;
  final PqcPrivateMessageCodec aliceCodec;
  final PqcPrivateMessageCodec bobCodec;
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
