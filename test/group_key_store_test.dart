import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_identity_service.dart';
import 'package:pqc_chat_app/core/device/device_key_service.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'package:pqc_chat_app/core/models/conversation.dart';
import 'package:pqc_chat_app/core/models/conversation_key_envelope.dart';
import 'package:pqc_chat_app/core/network/api_client.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';
import 'package:pqc_chat_app/features/chat/data/chat_remote_data_source.dart';
import 'package:pqc_chat_app/features/crypto/chat_crypto_exceptions.dart';
import 'package:pqc_chat_app/features/crypto/group_key_store.dart';

void main() {
  final groupConversation = Conversation(
    id: 1,
    type: 'group',
    title: 'General Group',
    participantIds: const [1, 2],
    lastMessagePreview: '',
    updatedAt: DateTime.parse('2026-07-04T00:00:00Z'),
  );

  test(
    'group key store rejects send when any participant lacks usable device key',
    () async {
      final algorithm = X25519();
      final alicePair = await algorithm.newKeyPair();
      final alicePairData = await alicePair.extract();
      final store = GroupKeyStore(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        deviceKeyService: _FakeDeviceKeyService(
          keyPairData: alicePairData,
          privateKeyBytes: await alicePair.extractPrivateKeyBytes(),
        ),
        remoteDataSource: _FakeChatRemoteDataSource(),
        secretStore: _MemorySecretStore(),
      );

      await expectLater(
        () => store.getOrCreateKey(
          conversation: groupConversation,
          usersById: {
            1: AppUser(
              id: 1,
              username: 'alice',
              displayName: 'Alice',
              devices: [
                AppUserDevice(
                  deviceId: 'alice-device',
                  deviceName: 'Alice Phone',
                  platform: 'android',
                  identityPublicKey: base64Encode(
                    alicePairData.publicKey.bytes,
                  ),
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
    },
  );

  test(
    'group key store uploads envelopes for every usable participant device',
    () async {
      final algorithm = X25519();
      final alicePair = await algorithm.newKeyPair();
      final bobPair = await algorithm.newKeyPair();
      final alicePairData = await alicePair.extract();
      final bobPairData = await bobPair.extract();
      final remote = _FakeChatRemoteDataSource();
      final store = GroupKeyStore(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        deviceKeyService: _FakeDeviceKeyService(
          keyPairData: alicePairData,
          privateKeyBytes: await alicePair.extractPrivateKeyBytes(),
        ),
        remoteDataSource: remote,
        secretStore: _MemorySecretStore(),
      );

      await store.getOrCreateKey(
        conversation: groupConversation,
        usersById: {
          1: AppUser(
            id: 1,
            username: 'alice',
            displayName: 'Alice',
            devices: [
              AppUserDevice(
                deviceId: 'alice-device',
                deviceName: 'Alice Phone',
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
                deviceName: 'Bob Phone',
                platform: 'android',
                identityPublicKey: base64Encode(bobPairData.publicKey.bytes),
                keyAlgorithm: 'x25519',
                preKeys: const [],
              ),
            ],
          ),
        },
      );

      expect(remote.lastSyncConversationId, 1);
      expect(remote.lastEnvelopes.length, 2);
      expect(remote.lastEnvelopes.map((item) => item.targetDeviceId).toSet(), {
        'alice-device',
        'bob-device',
      });
    },
  );
}

class _FakeChatRemoteDataSource extends ChatRemoteDataSource {
  _FakeChatRemoteDataSource() : super(apiClient: ApiClient());

  int? lastSyncConversationId;
  List<ConversationKeyEnvelopeUpload> lastEnvelopes = const [];
  final List<ConversationKeyEnvelope> stored = [];

  @override
  Future<List<ConversationKeyEnvelope>> fetchConversationKeyEnvelopes(
    int conversationId,
  ) async {
    return stored;
  }

  @override
  Future<void> syncConversationKeyEnvelopes({
    required int conversationId,
    required String keyId,
    required String algorithm,
    required List<ConversationKeyEnvelopeUpload> envelopes,
  }) async {
    lastSyncConversationId = conversationId;
    lastEnvelopes = envelopes;
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
