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

    expect(payload, startsWith('pqc:v2:'));
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

      final document = _decodePayload(payload);
      final wraps = (document['wraps'] as List).cast<Map>();

      expect(document['protocol_version'], 2);
      expect(document['sender_device_id'], 'alice-device');
      expect(
        wraps.map((item) => item['target_device_id']),
        containsAll(['alice-device', 'bob-device']),
      );
      expect(
        base64Decode(document['signing_public_key'] as String).length,
        DevicePqcSigningKeyService.publicKeyLength,
      );
      for (final wrap in wraps) {
        expect(
          base64Decode(wrap['kem_ciphertext'] as String).length,
          DevicePqcKeyService.ciphertextLength,
        );
        expect(base64Decode(wrap['nonce'] as String).length, 12);
        expect(
          base64Decode(wrap['ciphertext'] as String).length,
          DevicePqcKeyService.sharedSecretLength,
        );
        expect(base64Decode(wrap['mac'] as String).length, 16);
      }
      expect(base64Decode(document['content_nonce'] as String).length, 12);
      expect(
        base64Decode(document['content_ciphertext'] as String).length,
        greaterThanOrEqualTo(19),
      );
      expect(base64Decode(document['content_mac'] as String).length, 16);
      expect(
        base64Decode(document['signature'] as String).length,
        greaterThan(3000),
      );
      expect(payload.length, greaterThan(9000));
      expect(payload.contains('PQC payload metrics'), isFalse);
    },
  );

}

Map<String, dynamic> _decodePayload(String payload) {
  final encoded = payload.substring(PqcPrivateMessageCodec.prefix.length + 1);
  final padded = encoded.padRight(
    encoded.length + ((4 - encoded.length % 4) % 4),
    '=',
  );
  return jsonDecode(utf8.decode(base64Url.decode(padded)))
      as Map<String, dynamic>;
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
