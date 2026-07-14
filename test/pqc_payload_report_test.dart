// ignore_for_file: avoid_print

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

  test('prints pqc payload metrics', () async {
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

    final codec = PqcPrivateMessageCodec(
      deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
      devicePqcKeyService: alicePqc,
      devicePqcSigningKeyService: aliceSigning,
    );
    final payload = await codec.encrypt(
      currentUserId: 1,
      conversation: Conversation(
        id: 99,
        type: 'private',
        title: '',
        participantIds: const [1, 2],
        lastMessagePreview: '',
        updatedAt: DateTime.parse('2026-07-11T00:00:00Z'),
      ),
      plaintext: 'payload-inspection-message',
      usersById: usersById,
    );
    final encoded = payload.substring(PqcPrivateMessageCodec.prefix.length + 1);
    final padded = encoded.padRight(
      encoded.length + ((4 - encoded.length % 4) % 4),
      '=',
    );
    final document =
        jsonDecode(utf8.decode(base64Url.decode(padded)))
            as Map<String, dynamic>;
    final wraps = (document['wraps'] as List).cast<Map>();

    print('prefix=${PqcPrivateMessageCodec.prefix}');
    print('payload_chars=${payload.length}');
    print(
      'plaintext_visible=${payload.contains('payload-inspection-message')}',
    );
    print('recipient_envelope_count=${wraps.length}');
    print(
      'signing_public_key_bytes=${base64Decode(document['signing_public_key'] as String).length}',
    );
    print(
      'first_kem_ciphertext_bytes=${base64Decode(wraps.first['kem_ciphertext'] as String).length}',
    );
    print(
      'content_ciphertext_bytes=${base64Decode(document['content_ciphertext'] as String).length}',
    );
    print(
      'signature_bytes=${base64Decode(document['signature'] as String).length}',
    );

    expect(payload, startsWith('pqc:v2:'));
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
