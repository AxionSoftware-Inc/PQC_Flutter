import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_identity_service.dart';
import 'package:pqc_chat_app/core/device/device_key_service.dart';
import 'package:pqc_chat_app/core/device/device_prekey_service.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'package:pqc_chat_app/core/models/conversation.dart';
import 'package:pqc_chat_app/features/crypto/chat_crypto_exceptions.dart';
import 'package:pqc_chat_app/features/crypto/group_key_store.dart';
import 'package:pqc_chat_app/features/crypto/message_codec.dart';
import 'package:pqc_chat_app/features/crypto/outbound_message_cache.dart';
import 'package:pqc_chat_app/features/crypto/peer_prekey_selection_service.dart';
import 'package:pqc_chat_app/features/crypto/private_session_store.dart';

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
      deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
      deviceKeyService: aliceDevice,
      devicePreKeyService: _FakeDevicePreKeyService(),
      privateSessionStore: _FakePrivateSessionStore(),
      outboundMessageCache: _FakeOutboundMessageCache(),
      groupKeyStore: _FakeGroupKeyStore(),
      peerPreKeySelectionService: _FakePeerPreKeySelectionService(),
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
                preKeys: const [],
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
              preKeys: const [],
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
              preKeys: const [],
            ),
          ],
        ),
      };

      final aliceCodec = X25519CipherMessageCodec(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        deviceKeyService: aliceDevice,
        devicePreKeyService: _FakeDevicePreKeyService(),
        privateSessionStore: _FakePrivateSessionStore(),
        peerPreKeySelectionService: _FakePeerPreKeySelectionService(),
      );
      final bobCodec = X25519CipherMessageCodec(
        deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
        deviceKeyService: bobDevice,
        devicePreKeyService: _FakeDevicePreKeyService(),
        privateSessionStore: _FakePrivateSessionStore(),
        peerPreKeySelectionService: _FakePeerPreKeySelectionService(),
      );

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

      expect(encrypted, startsWith('x25519:v3:'));
      expect(encrypted.contains('salom laylo'), isFalse);
      expect(decrypted, 'salom laylo');
    },
  );

  test(
    'x25519 v4 bootstrap payload can still decrypt after peer registry key changes',
    () async {
      final algorithm = X25519();
      final alicePair = await algorithm.newKeyPair();
      final bobOldPair = await algorithm.newKeyPair();
      final bobNewPair = await algorithm.newKeyPair();
      final alicePairData = await alicePair.extract();
      final bobOldPairData = await bobOldPair.extract();
      final bobNewPairData = await bobNewPair.extract();

      final aliceDevice = _FakeDeviceKeyService(
        keyPairData: alicePairData,
        privateKeyBytes: await alicePair.extractPrivateKeyBytes(),
      );
      final bobDevice = _FakeDeviceKeyService(
        keyPairData: bobOldPairData,
        privateKeyBytes: await bobOldPair.extractPrivateKeyBytes(),
      );
      final bobPreKeyService = _FakeDevicePreKeyService({
        'bob-prekey-1': bobOldPairData.copy(),
      });

      final aliceCodec = X25519CipherMessageCodec(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        deviceKeyService: aliceDevice,
        devicePreKeyService: _FakeDevicePreKeyService(),
        privateSessionStore: _FakePrivateSessionStore(),
        peerPreKeySelectionService: _FakePeerPreKeySelectionService(),
      );
      final bobCodec = X25519CipherMessageCodec(
        deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
        deviceKeyService: bobDevice,
        devicePreKeyService: bobPreKeyService,
        privateSessionStore: _FakePrivateSessionStore(),
        peerPreKeySelectionService: _FakePeerPreKeySelectionService(),
      );

      final encrypted = await aliceCodec.encrypt(
        currentUserId: 1,
        conversation: privateConversation,
        plaintext: 'history survives rotation',
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
                preKeys: const [],
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
                identityPublicKey: base64Encode(bobOldPairData.publicKey.bytes),
                keyAlgorithm: 'x25519',
                preKeys: [
                  AppUserPreKey(
                    keyId: 'bob-prekey-1',
                    publicKey: base64Encode(bobOldPairData.publicKey.bytes),
                  ),
                ],
              ),
            ],
          ),
        },
      );

      final decrypted = await bobCodec.decrypt(
        currentUserId: 2,
        conversation: privateConversation,
        payload: encrypted,
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
                preKeys: const [],
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
                identityPublicKey: base64Encode(bobNewPairData.publicKey.bytes),
                keyAlgorithm: 'x25519',
                preKeys: const [],
              ),
            ],
          ),
        },
      );

      expect(encrypted, startsWith('x25519:v4:'));
      expect(decrypted, 'history survives rotation');
      expect(bobPreKeyService.removedKeyIds, ['bob-prekey-1']);
    },
  );

  test(
    'subsequent private messages stay decryptable without stored session state',
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
      final aliceSessions = _FakePrivateSessionStore();
      final bobSessions = _FakePrivateSessionStore();
      final bobPreKeys = _FakeDevicePreKeyService({
        'bob-prekey-1': bobPairData.copy(),
      });

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
              preKeys: const [],
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
              preKeys: [
                AppUserPreKey(
                  keyId: 'bob-prekey-1',
                  publicKey: base64Encode(bobPairData.publicKey.bytes),
                ),
              ],
            ),
          ],
        ),
      };

      final aliceCodec = X25519CipherMessageCodec(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        deviceKeyService: aliceDevice,
        devicePreKeyService: _FakeDevicePreKeyService(),
        privateSessionStore: aliceSessions,
        peerPreKeySelectionService: _FakePeerPreKeySelectionService(),
      );
      final bobCodec = X25519CipherMessageCodec(
        deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
        deviceKeyService: bobDevice,
        devicePreKeyService: bobPreKeys,
        privateSessionStore: bobSessions,
        peerPreKeySelectionService: _FakePeerPreKeySelectionService(),
      );

      final bootstrapPayload = await aliceCodec.encrypt(
        currentUserId: 1,
        conversation: privateConversation,
        plaintext: 'hello bootstrap',
        usersById: usersById,
      );
      final bootstrapCleartext = await bobCodec.decrypt(
        currentUserId: 2,
        conversation: privateConversation,
        payload: bootstrapPayload,
        usersById: usersById,
      );
      final followupPayload = await aliceCodec.encrypt(
        currentUserId: 1,
        conversation: privateConversation,
        plaintext: 'hello followup',
        usersById: {
          ...usersById,
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
                preKeys: const [],
              ),
            ],
          ),
        },
      );
      final followupCleartext = await bobCodec.decrypt(
        currentUserId: 2,
        conversation: privateConversation,
        payload: followupPayload,
        usersById: {
          ...usersById,
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
                preKeys: const [],
              ),
            ],
          ),
        },
      );

      expect(bootstrapPayload, startsWith('x25519:v4:'));
      expect(bootstrapCleartext, 'hello bootstrap');
      expect(followupPayload, startsWith('x25519:v3:'));
      expect(followupCleartext, 'hello followup');
    },
  );

  test(
    'stale private session is discarded when peer identity changes',
    () async {
      final algorithm = X25519();
      final alicePair = await algorithm.newKeyPair();
      final bobOldPair = await algorithm.newKeyPair();
      final bobNewPair = await algorithm.newKeyPair();
      final alicePairData = await alicePair.extract();
      final bobOldPairData = await bobOldPair.extract();
      final bobNewPairData = await bobNewPair.extract();
      final aliceSessions = _FakePrivateSessionStore()
        ..seedSession(
          const PrivateSessionState(
            conversationId: 2,
            peerDeviceId: 'bob-device',
            peerIdentityPublicKey: 'old-key',
            rootKey: 'stale-root',
            sendingChainKey: 'stale-send',
            receivingChainKey: 'stale-recv',
            nextLocalCounter: 3,
            nextRemoteCounter: 0,
            skippedRemoteMessageKeys: {},
            establishedBy: 'session:v1',
          ),
        );

      final aliceCodec = X25519CipherMessageCodec(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        deviceKeyService: _FakeDeviceKeyService(
          keyPairData: alicePairData,
          privateKeyBytes: await alicePair.extractPrivateKeyBytes(),
        ),
        devicePreKeyService: _FakeDevicePreKeyService(),
        privateSessionStore: aliceSessions,
        peerPreKeySelectionService: _FakePeerPreKeySelectionService(),
      );

      final payload = await aliceCodec.encrypt(
        currentUserId: 1,
        conversation: privateConversation,
        plaintext: 'refresh session',
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
                preKeys: const [],
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
                identityPublicKey: base64Encode(bobNewPairData.publicKey.bytes),
                keyAlgorithm: 'x25519',
                preKeys: [
                  AppUserPreKey(
                    keyId: 'bob-prekey-2',
                    publicKey: base64Encode(bobOldPairData.publicKey.bytes),
                  ),
                ],
              ),
            ],
          ),
        },
      );

      final refreshedSession = await aliceSessions.readSession(
        conversationId: 2,
        peerDeviceId: 'bob-device',
      );

      expect(payload, startsWith('x25519:v4:'));
      expect(
        refreshedSession?.peerIdentityPublicKey,
        base64Encode(bobNewPairData.publicKey.bytes),
      );
      expect(refreshedSession?.rootKey, isNot('stale-root'));
    },
  );

  test(
    'hybrid services return cached plaintext for self-sent private messages',
    () async {
      final algorithm = X25519();
      final alicePair = await algorithm.newKeyPair();
      final bobPair = await algorithm.newKeyPair();
      final alicePairData = await alicePair.extract();
      final bobPairData = await bobPair.extract();
      final cache = _FakeOutboundMessageCache();
      final aliceSessions = _FakePrivateSessionStore();

      final composer = HybridMessageComposerService(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        deviceKeyService: _FakeDeviceKeyService(
          keyPairData: alicePairData,
          privateKeyBytes: await alicePair.extractPrivateKeyBytes(),
        ),
        devicePreKeyService: _FakeDevicePreKeyService(),
        privateSessionStore: aliceSessions,
        outboundMessageCache: cache,
        groupKeyStore: _FakeGroupKeyStore(),
        peerPreKeySelectionService: _FakePeerPreKeySelectionService(),
      );
      final decoder = HybridMessageDecoderService(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        deviceKeyService: _FakeDeviceKeyService(
          keyPairData: alicePairData,
          privateKeyBytes: await alicePair.extractPrivateKeyBytes(),
        ),
        devicePreKeyService: _FakeDevicePreKeyService(),
        privateSessionStore: aliceSessions,
        outboundMessageCache: cache,
        groupKeyStore: _FakeGroupKeyStore(),
      );

      final payload = await composer.compose(
        currentUserId: 1,
        conversation: privateConversation,
        plaintext: 'self visible',
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
                preKeys: const [],
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
                preKeys: const [],
              ),
            ],
          ),
        },
      );

      final decrypted = await decoder.decode(
        currentUserId: 1,
        conversation: privateConversation,
        payload: payload,
        usersById: const {},
      );

      expect(decrypted, 'self visible');
    },
  );

  test(
    'hybrid decoder caches inbound bootstrap plaintext after consuming one-time prekey',
    () async {
      final algorithm = X25519();
      final alicePair = await algorithm.newKeyPair();
      final bobPair = await algorithm.newKeyPair();
      final alicePairData = await alicePair.extract();
      final bobPairData = await bobPair.extract();
      final cache = _FakeOutboundMessageCache();
      final bobSessions = _FakePrivateSessionStore();
      final bobPreKeys = _FakeDevicePreKeyService({
        'bob-prekey-1': bobPairData.copy(),
      });

      final aliceCodec = X25519CipherMessageCodec(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        deviceKeyService: _FakeDeviceKeyService(
          keyPairData: alicePairData,
          privateKeyBytes: await alicePair.extractPrivateKeyBytes(),
        ),
        devicePreKeyService: _FakeDevicePreKeyService(),
        privateSessionStore: _FakePrivateSessionStore(),
        peerPreKeySelectionService: _FakePeerPreKeySelectionService(),
      );
      final decoder = HybridMessageDecoderService(
        deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
        deviceKeyService: _FakeDeviceKeyService(
          keyPairData: bobPairData,
          privateKeyBytes: await bobPair.extractPrivateKeyBytes(),
        ),
        devicePreKeyService: bobPreKeys,
        privateSessionStore: bobSessions,
        outboundMessageCache: cache,
        groupKeyStore: _FakeGroupKeyStore(),
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
              preKeys: const [],
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
              preKeys: [
                AppUserPreKey(
                  keyId: 'bob-prekey-1',
                  publicKey: base64Encode(bobPairData.publicKey.bytes),
                ),
              ],
            ),
          ],
        ),
      };

      final payload = await aliceCodec.encrypt(
        currentUserId: 1,
        conversation: privateConversation,
        plaintext: 'consumed once',
        usersById: usersById,
      );

      final firstDecode = await decoder.decode(
        currentUserId: 2,
        conversation: privateConversation,
        payload: payload,
        usersById: usersById,
      );
      final secondDecode = await decoder.decode(
        currentUserId: 2,
        conversation: privateConversation,
        payload: payload,
        usersById: usersById,
      );

      expect(firstDecode, 'consumed once');
      expect(secondDecode, 'consumed once');
      expect(bobPreKeys.removedKeyIds, ['bob-prekey-1']);
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

class _FakeDevicePreKeyService extends DevicePreKeyService {
  _FakeDevicePreKeyService([Map<String, SimpleKeyPair>? keyPairs])
    : _keyPairs = keyPairs ?? <String, SimpleKeyPair>{};

  final Map<String, SimpleKeyPair> _keyPairs;
  final List<String> removedKeyIds = [];

  @override
  Future<List<Map<String, dynamic>>> ensurePreKeys({
    int minimumCount = 12,
  }) async {
    return const [];
  }

  @override
  Future<SimpleKeyPair?> takePreKeyPair(String keyId) async {
    return _keyPairs[keyId];
  }

  @override
  Future<void> removePreKey(String keyId) async {
    removedKeyIds.add(keyId);
    _keyPairs.remove(keyId);
  }
}

class _FakePrivateSessionStore extends PrivateSessionStore {
  _FakePrivateSessionStore() : super();

  final Map<String, PrivateSessionState> _sessions = {};

  void seedSession(PrivateSessionState session) {
    _sessions['${session.conversationId}:${session.peerDeviceId}'] = session;
  }

  @override
  Future<PrivateSessionState?> readSession({
    required int conversationId,
    required String peerDeviceId,
  }) async {
    return _sessions['$conversationId:$peerDeviceId'];
  }

  @override
  Future<bool> hasSession({
    required int conversationId,
    required String peerDeviceId,
  }) async {
    return _sessions.containsKey('$conversationId:$peerDeviceId');
  }

  @override
  Future<bool> hasMatchingSession({
    required int conversationId,
    required String peerDeviceId,
    required String peerIdentityPublicKey,
  }) async {
    final session = _sessions['$conversationId:$peerDeviceId'];
    if (session == null) {
      return false;
    }
    return session.peerIdentityPublicKey == peerIdentityPublicKey;
  }

  @override
  Future<void> writeSession(PrivateSessionState session) async {
    _sessions['${session.conversationId}:${session.peerDeviceId}'] = session;
  }

  @override
  Future<void> establishSession({
    required int conversationId,
    required String peerDeviceId,
    required String peerIdentityPublicKey,
    required String rootKey,
    required String sendingChainKey,
    required String receivingChainKey,
    required String establishedBy,
  }) async {
    final key = '$conversationId:$peerDeviceId';
    final existing = _sessions[key];
    if (existing != null && existing.rootKey == rootKey) {
      return;
    }
    _sessions[key] = PrivateSessionState(
      conversationId: conversationId,
      peerDeviceId: peerDeviceId,
      peerIdentityPublicKey: peerIdentityPublicKey,
      rootKey: rootKey,
      sendingChainKey: sendingChainKey,
      receivingChainKey: receivingChainKey,
      nextLocalCounter: 0,
      nextRemoteCounter: 0,
      skippedRemoteMessageKeys: const {},
      establishedBy: establishedBy,
    );
  }

  @override
  Future<int> takeNextOutgoingCounter({
    required int conversationId,
    required String peerDeviceId,
  }) async {
    final key = '$conversationId:$peerDeviceId';
    final session = _sessions[key]!;
    final counter = session.nextLocalCounter;
    _sessions[key] = session.copyWith(nextLocalCounter: counter + 1);
    return counter;
  }

  @override
  Future<void> deleteSession({
    required int conversationId,
    required String peerDeviceId,
  }) async {
    _sessions.remove('$conversationId:$peerDeviceId');
  }
}

class _FakeOutboundMessageCache extends OutboundMessageCache {
  _FakeOutboundMessageCache() : super();

  final Map<String, String> _cache = {};

  @override
  Future<void> storePlaintext({
    required String payload,
    required String plaintext,
  }) async {
    _cache[payload] = plaintext;
  }

  @override
  Future<String?> readPlaintext(String payload) async {
    return _cache[payload];
  }
}

class _FakePeerPreKeySelectionService extends PeerPreKeySelectionService {
  @override
  Future<AppUserPreKey?> reserveNextPreKey(AppUserDevice device) async {
    for (final preKey in device.preKeys) {
      if (preKey.hasUsablePublicKey) {
        return preKey;
      }
    }
    return null;
  }
}
