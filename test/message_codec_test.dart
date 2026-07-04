import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_key_service.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'package:pqc_chat_app/core/models/conversation.dart';
import 'package:pqc_chat_app/features/crypto/chat_crypto_exceptions.dart';
import 'package:pqc_chat_app/features/crypto/group_key_store.dart';
import 'package:pqc_chat_app/features/crypto/message_codec.dart';

void main() {
  final privateConversation = Conversation(
    id: 2,
    type: 'private',
    title: '',
    participantIds: const [1, 2],
    lastMessagePreview: '',
    updatedAt: DateTime.parse('2026-07-03T00:00:00Z'),
  );

  final groupConversation = Conversation(
    id: 1,
    type: 'group',
    title: 'General Group',
    participantIds: const [1, 2, 3],
    lastMessagePreview: '',
    updatedAt: DateTime.parse('2026-07-03T00:00:00Z'),
  );

  test('legacy demo payloads can still be decrypted', () async {
    final codec = DemoCipherMessageCodec();
    final decrypted = await codec.decrypt(
      conversation: groupConversation,
      payload:
          'enc:v1:C4252Swj8NzQ17Yl:GNF7ICuN7qgrCg==:FudYqiNkw7no55e87uKSOg==',
    );

    expect(decrypted, 'yana salom');
  });

  test('private chat requires peer public key for new messages', () async {
    final algorithm = X25519();
    final alicePair = await algorithm.newKeyPair();
    final alicePairData = await alicePair.extract();
    final aliceDevice = _FakeDeviceKeyService(
      keyPairData: alicePairData,
      privateKeyBytes: await alicePair.extractPrivateKeyBytes(),
    );

    final composer = HybridMessageComposerService(
      deviceKeyService: aliceDevice,
      groupKeyStore: _FakeGroupKeyStore(),
    );

    await expectLater(
      () => composer.compose(
        currentUserId: 1,
        conversation: privateConversation,
        plaintext: 'test',
        usersById: {
          1: AppUser(
            id: 1,
            username: 'alice',
            displayName: 'Alice',
            devices: [
              AppUserDevice(
                deviceId: 'alice-device',
                deviceName: 'alice',
                platform: 'android',
                identityPublicKey: base64Encode(alicePairData.publicKey.bytes),
                keyAlgorithm: 'x25519',
              ),
            ],
          ),
          2: const AppUser(
            id: 2,
            username: 'bob',
            displayName: 'Bob',
            devices: [],
          ),
        },
      ),
      throwsA(isA<ChatEncryptionException>()),
    );
  });

  test(
    'x25519 private chat encrypts and decrypts with matching keys',
    () async {
      final algorithm = X25519();
      final alicePair = await algorithm.newKeyPair();
      final bobPair = await algorithm.newKeyPair();
      final alicePairData = await alicePair.extract();
      final bobPairData = await bobPair.extract();

      final aliceDevice = _FakeDeviceKeyService(
        keyPairData: alicePairData,
        privateKeyBytes: await alicePair.extractPrivateKeyBytes(),
      );
      final bobDevice = _FakeDeviceKeyService(
        keyPairData: bobPairData,
        privateKeyBytes: await bobPair.extractPrivateKeyBytes(),
      );

      final usersById = {
        1: AppUser(
          id: 1,
          username: 'alice',
          displayName: 'Alice',
          devices: [
            AppUserDevice(
              deviceId: 'alice-device',
              deviceName: 'alice',
              platform: 'android',
              identityPublicKey: base64Encode(alicePairData.publicKey.bytes),
              keyAlgorithm: 'x25519',
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
              deviceName: 'bob',
              platform: 'android',
              identityPublicKey: base64Encode(bobPairData.publicKey.bytes),
              keyAlgorithm: 'x25519',
            ),
          ],
        ),
      };

      final aliceCodec = X25519CipherMessageCodec(
        deviceKeyService: aliceDevice,
      );
      final bobCodec = X25519CipherMessageCodec(deviceKeyService: bobDevice);

      final encrypted = await aliceCodec.encrypt(
        currentUserId: 1,
        conversation: privateConversation,
        plaintext: 'salom laylo',
        usersById: usersById,
      );
      final decrypted = await bobCodec.decrypt(
        currentUserId: 2,
        conversation: privateConversation,
        payload: encrypted,
        usersById: usersById,
      );

      expect(encrypted, startsWith('x25519:v1:'));
      expect(encrypted.contains('salom laylo'), isFalse);
      expect(decrypted, 'salom laylo');
    },
  );

  test(
    'group chat encrypts and decrypts with shared group key material',
    () async {
      final groupStore = _FakeGroupKeyStore();
      final codec = GroupCipherMessageCodec(groupKeyStore: groupStore);
      final usersById = {
        1: const AppUser(
          id: 1,
          username: 'alice',
          displayName: 'Alice',
          devices: [],
        ),
        2: const AppUser(
          id: 2,
          username: 'bob',
          displayName: 'Bob',
          devices: [],
        ),
        3: const AppUser(
          id: 3,
          username: 'sardor',
          displayName: 'Sardor',
          devices: [],
        ),
      };

      final encrypted = await codec.encrypt(
        conversation: groupConversation,
        plaintext: 'salom group',
        usersById: usersById,
      );
      final decrypted = await codec.decrypt(
        conversation: groupConversation,
        payload: encrypted,
        usersById: usersById,
      );

      expect(encrypted, startsWith('group:v1:'));
      expect(encrypted.contains('salom group'), isFalse);
      expect(decrypted, 'salom group');
    },
  );

  test(
    'group chat returns decrypt error when requested key is missing',
    () async {
      final codec = GroupCipherMessageCodec(
        groupKeyStore: _FakeGroupKeyStore(),
      );
      final decrypted = await codec.decrypt(
        conversation: groupConversation,
        payload: 'group:v1:missing-key:bm9uY2U=:Y2lwaGVy:dGFn',
        usersById: const {},
      );

      expect(decrypted, '[decrypt-error]');
    },
  );
}

class _FakeGroupKeyStore implements GroupKeyProvider {
  _FakeGroupKeyStore();

  final Map<String, List<int>> _keys = {};

  @override
  Future<GroupKeyMaterial> getOrCreateKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    final keyId = 'test-group-key';
    final key = _keys.putIfAbsent(
      '${conversation.id}:$keyId',
      () => List<int>.generate(32, (index) => index),
    );
    return GroupKeyMaterial(keyId: keyId, secretKeyBytes: key);
  }

  @override
  Future<GroupKeyMaterial?> getExistingKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    String? requestedKeyId,
  }) async {
    final keyId = requestedKeyId ?? 'test-group-key';
    final key = _keys['${conversation.id}:$keyId'];
    if (key == null) {
      return null;
    }
    return GroupKeyMaterial(keyId: keyId, secretKeyBytes: key);
  }
}

class _FakeDeviceKeyService extends DeviceKeyService {
  _FakeDeviceKeyService({
    required this.keyPairData,
    required this.privateKeyBytes,
  });

  final SimpleKeyPairData keyPairData;
  final List<int> privateKeyBytes;

  @override
  Future<DeviceKeyMaterial> getOrCreateKeyMaterial() async {
    return DeviceKeyMaterial(
      publicKey: base64Encode(keyPairData.publicKey.bytes),
      privateKey: base64Encode(privateKeyBytes),
      algorithm: 'x25519',
    );
  }

  @override
  Future<SimpleKeyPair> getIdentityKeyPair() async {
    return keyPairData.copy();
  }
}
