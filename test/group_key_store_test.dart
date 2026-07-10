import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_identity_service.dart';
import 'package:pqc_chat_app/core/device/device_pqc_key_service.dart';
import 'package:pqc_chat_app/core/device/device_pqc_signing_key_service.dart';
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
    'group key store rejects send when any participant lacks usable pqc device key',
    () async {
      final aliceSecrets = _MemorySecretStore();
      final alicePqc = DevicePqcKeyService(secretStore: aliceSecrets);
      final aliceSigning = DevicePqcSigningKeyService(
        secretStore: aliceSecrets,
      );
      final alicePqcMaterial = await alicePqc.getOrCreateKeyMaterial();
      final aliceSigningMaterial = await aliceSigning.getOrCreateKeyMaterial();

      final store = GroupKeyStore(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        devicePqcKeyService: alicePqc,
        devicePqcSigningKeyService: aliceSigning,
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
                  identityPublicKey: '',
                  keyAlgorithm: '',
                  pqcPublicKey: alicePqcMaterial.publicKey,
                  pqcAlgorithm: alicePqcMaterial.algorithm,
                  pqcSigningPublicKey: aliceSigningMaterial.publicKey,
                  pqcSigningAlgorithm: aliceSigningMaterial.algorithm,
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
    'group key store uploads pqc envelopes for every usable participant device',
    () async {
      final aliceSecrets = _MemorySecretStore();
      final bobSecrets = _MemorySecretStore();
      final alicePqc = DevicePqcKeyService(secretStore: aliceSecrets);
      final bobPqc = DevicePqcKeyService(secretStore: bobSecrets);
      final aliceSigning = DevicePqcSigningKeyService(
        secretStore: aliceSecrets,
      );
      final bobSigning = DevicePqcSigningKeyService(secretStore: bobSecrets);
      final alicePqcMaterial = await alicePqc.getOrCreateKeyMaterial();
      final bobPqcMaterial = await bobPqc.getOrCreateKeyMaterial();
      final aliceSigningMaterial = await aliceSigning.getOrCreateKeyMaterial();
      final bobSigningMaterial = await bobSigning.getOrCreateKeyMaterial();
      final remote = _FakeChatRemoteDataSource();
      final store = GroupKeyStore(
        deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
        devicePqcKeyService: alicePqc,
        devicePqcSigningKeyService: aliceSigning,
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
                deviceName: 'Bob Phone',
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
        },
      );

      expect(remote.lastSyncConversationId, 1);
      expect(remote.lastAlgorithm, 'group-ml-kem-768-aesgcm-v1');
      expect(remote.lastEnvelopes.length, 2);
      expect(remote.lastEnvelopes.map((item) => item.targetDeviceId).toSet(), {
        'alice-device',
        'bob-device',
      });
      expect(
        remote.lastEnvelopes.first.wrappedKey,
        startsWith('group-wrap:pqc:v1:'),
      );
    },
  );

  test('group key store decrypts pqc envelopes for current device', () async {
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
    final remote = _FakeChatRemoteDataSource();

    final aliceStore = GroupKeyStore(
      deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
      devicePqcKeyService: alicePqc,
      devicePqcSigningKeyService: aliceSigning,
      remoteDataSource: remote,
      secretStore: _MemorySecretStore(),
    );
    final bobStore = GroupKeyStore(
      deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
      devicePqcKeyService: bobPqc,
      devicePqcSigningKeyService: bobSigning,
      remoteDataSource: remote,
      secretStore: _MemorySecretStore(),
    );

    final usersById = {
      1: AppUser(
        id: 1,
        username: 'alice',
        displayName: 'Alice',
        devices: [
          AppUserDevice(
            deviceId: 'alice-device',
            deviceName: 'Alice Phone',
            platform: 'android',
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
            deviceName: 'Bob Phone',
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

    final aliceKey = await aliceStore.getOrCreateKey(
      conversation: groupConversation,
      usersById: usersById,
    );
    final bobKey = await bobStore.getExistingKey(
      conversation: groupConversation,
      usersById: usersById,
      requestedKeyId: aliceKey.keyId,
    );

    expect(bobKey, isNotNull);
    expect(
      base64Encode(bobKey!.secretKeyBytes),
      base64Encode(aliceKey.secretKeyBytes),
    );
  });
}

class _FakeChatRemoteDataSource extends ChatRemoteDataSource {
  _FakeChatRemoteDataSource() : super(apiClient: ApiClient());

  int? lastSyncConversationId;
  String? lastAlgorithm;
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
    lastAlgorithm = algorithm;
    lastEnvelopes = envelopes;
    final now = DateTime.parse('2026-07-11T00:00:00Z');
    stored
      ..clear()
      ..addAll(
        envelopes.map(
          (item) => ConversationKeyEnvelope(
            keyId: keyId,
            algorithm: algorithm,
            targetDeviceId: item.targetDeviceId,
            senderDeviceId: 'alice-device',
            wrappedKey: item.wrappedKey,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      );
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
