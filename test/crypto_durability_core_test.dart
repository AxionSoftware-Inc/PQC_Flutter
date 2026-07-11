import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_identity_service.dart';
import 'package:pqc_chat_app/core/device/device_key_service.dart';
import 'package:pqc_chat_app/core/device/device_pqc_key_service.dart';
import 'package:pqc_chat_app/core/device/device_pqc_signing_key_service.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'package:pqc_chat_app/core/models/conversation.dart';
import 'package:pqc_chat_app/core/models/conversation_key_envelope.dart';
import 'package:pqc_chat_app/core/network/api_client.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';
import 'package:pqc_chat_app/features/chat/data/chat_remote_data_source.dart';
import 'package:pqc_chat_app/features/crypto/durability/crypto_backup_service.dart';
import 'package:pqc_chat_app/features/crypto/durability/crypto_durability_models.dart';
import 'package:pqc_chat_app/features/crypto/durability/key_material_registry.dart';
import 'package:pqc_chat_app/features/crypto/group_key_store.dart';
import 'package:pqc_chat_app/features/crypto/message_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('encrypted backup restores historical private decrypt after reinstall', () async {
    final aliceSecrets = _MemorySecretStore();
    final bobOldSecrets = _MemorySecretStore();

    final alicePqc = DevicePqcKeyService(secretStore: aliceSecrets);
    final aliceSigning = DevicePqcSigningKeyService(secretStore: aliceSecrets);
    final bobOldPqc = DevicePqcKeyService(secretStore: bobOldSecrets);
    final bobOldSigning = DevicePqcSigningKeyService(secretStore: bobOldSecrets);
    final bobOldIdentityKeys = DeviceKeyService(secretStore: bobOldSecrets);

    final alicePqcMaterial = await alicePqc.getOrCreateKeyMaterial();
    final aliceSigningMaterial = await aliceSigning.getOrCreateKeyMaterial();
    final bobOldPqcMaterial = await bobOldPqc.getOrCreateKeyMaterial();
    final bobOldSigningMaterial = await bobOldSigning.getOrCreateKeyMaterial();

    final conversation = Conversation(
      id: 77,
      type: 'private',
      title: '',
      participantIds: const [1, 2],
      lastMessagePreview: '',
      updatedAt: DateTime.parse('2026-07-11T00:00:00Z'),
    );
    final usersById = {
      1: AppUser(
        id: 1,
        username: 'alice',
        displayName: 'Alice',
        devices: [
          AppUserDevice(
            deviceId: 'alice-device',
            deviceName: 'Alice',
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
            deviceName: 'Bob',
            platform: 'android',
            identityPublicKey: '',
            keyAlgorithm: '',
            pqcPublicKey: bobOldPqcMaterial.publicKey,
            pqcAlgorithm: bobOldPqcMaterial.algorithm,
            pqcSigningPublicKey: bobOldSigningMaterial.publicKey,
            pqcSigningAlgorithm: bobOldSigningMaterial.algorithm,
          ),
        ],
      ),
    };

    final bobOldRegistry = KeyMaterialRegistry(
      deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
      deviceKeyService: bobOldIdentityKeys,
      devicePqcKeyService: bobOldPqc,
      devicePqcSigningKeyService: bobOldSigning,
      secretStore: bobOldSecrets,
    );
    await bobOldRegistry.ensureCurrentKeysetRegistered();
    final backupService = CryptoBackupService(
      keyMaterialRegistry: bobOldRegistry,
      secretStore: bobOldSecrets,
    );

    final aliceCodec = PqcPrivateMessageCodec(
      deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
      devicePqcKeyService: alicePqc,
      devicePqcSigningKeyService: aliceSigning,
    );
    final payload = await aliceCodec.encrypt(
      currentUserId: 1,
      conversation: conversation,
      plaintext: 'historical hello',
      usersById: usersById,
    );

    final encryptedBackup = await backupService.exportEncryptedBackup(
      const BackupExportRequest(recoveryPassphrase: 'ultra-secret-passphrase'),
    );

    final bobNewSecrets = _MemorySecretStore();
    final bobNewRegistry = KeyMaterialRegistry(secretStore: bobNewSecrets);
    final bobNewBackupService = CryptoBackupService(
      keyMaterialRegistry: bobNewRegistry,
      secretStore: bobNewSecrets,
    );
    await bobNewBackupService.importEncryptedBackup(
      BackupImportRequest(
        recoveryPassphrase: 'ultra-secret-passphrase',
        encryptedBlob: encryptedBackup,
      ),
    );

    final bobNewCodec = PqcPrivateMessageCodec(
      deviceIdentityService: _FakeDeviceIdentityService('bob-new-device'),
      devicePqcKeyService: DevicePqcKeyService(secretStore: bobNewSecrets),
      devicePqcSigningKeyService: DevicePqcSigningKeyService(
        secretStore: bobNewSecrets,
      ),
      keyMaterialRegistry: bobNewRegistry,
    );

    final restoredPlaintext = await bobNewCodec.decrypt(
      currentUserId: 2,
      conversation: conversation,
      payload: payload,
      usersById: usersById,
    );

    expect(restoredPlaintext, 'historical hello');
    final historicalCheck = await bobNewRegistry.historicalDecryptCheck();
    expect(historicalCheck.hasHistoricalCapability, isTrue);
  });

  test('invalid recovery passphrase rejects encrypted backup import', () async {
    final secrets = _MemorySecretStore();
    final registry = KeyMaterialRegistry(
      deviceIdentityService: _FakeDeviceIdentityService('device-a'),
      deviceKeyService: DeviceKeyService(secretStore: secrets),
      devicePqcKeyService: DevicePqcKeyService(secretStore: secrets),
      devicePqcSigningKeyService: DevicePqcSigningKeyService(
        secretStore: secrets,
      ),
      secretStore: secrets,
    );
    await registry.ensureCurrentKeysetRegistered();
    final backupService = CryptoBackupService(
      keyMaterialRegistry: registry,
      secretStore: secrets,
    );
    final blob = await backupService.exportEncryptedBackup(
      const BackupExportRequest(recoveryPassphrase: 'correct-pass'),
    );

    final importedRegistry = KeyMaterialRegistry(secretStore: _MemorySecretStore());
    final importService = CryptoBackupService(
      keyMaterialRegistry: importedRegistry,
      secretStore: _MemorySecretStore(),
    );

    await expectLater(
      () => importService.importEncryptedBackup(
        BackupImportRequest(
          recoveryPassphrase: 'wrong-pass',
          encryptedBlob: blob,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('restored local group key decrypts old group message after reinstall', () async {
    final aliceSecrets = _MemorySecretStore();
    final bobOldSecrets = _MemorySecretStore();

    final alicePqc = DevicePqcKeyService(secretStore: aliceSecrets);
    final bobOldPqc = DevicePqcKeyService(secretStore: bobOldSecrets);
    final aliceSigning = DevicePqcSigningKeyService(secretStore: aliceSecrets);
    final bobOldSigning = DevicePqcSigningKeyService(secretStore: bobOldSecrets);
    final alicePqcMaterial = await alicePqc.getOrCreateKeyMaterial();
    final bobOldPqcMaterial = await bobOldPqc.getOrCreateKeyMaterial();
    final aliceSigningMaterial = await aliceSigning.getOrCreateKeyMaterial();
    final bobOldSigningMaterial = await bobOldSigning.getOrCreateKeyMaterial();

    final conversation = Conversation(
      id: 19,
      type: 'group',
      title: 'General',
      participantIds: const [1, 2],
      lastMessagePreview: '',
      updatedAt: DateTime.parse('2026-07-11T00:00:00Z'),
    );
    final usersById = {
      1: AppUser(
        id: 1,
        username: 'alice',
        displayName: 'Alice',
        devices: [
          AppUserDevice(
            deviceId: 'alice-device',
            deviceName: 'Alice',
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
            deviceName: 'Bob',
            platform: 'android',
            identityPublicKey: '',
            keyAlgorithm: '',
            pqcPublicKey: bobOldPqcMaterial.publicKey,
            pqcAlgorithm: bobOldPqcMaterial.algorithm,
            pqcSigningPublicKey: bobOldSigningMaterial.publicKey,
            pqcSigningAlgorithm: bobOldSigningMaterial.algorithm,
          ),
        ],
      ),
    };

    final remote = _FakeChatRemoteDataSource();
    final aliceStore = GroupKeyStore(
      deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
      devicePqcKeyService: alicePqc,
      devicePqcSigningKeyService: aliceSigning,
      remoteDataSource: remote,
      secretStore: aliceSecrets,
    );
    final bobOldStore = GroupKeyStore(
      deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
      devicePqcKeyService: bobOldPqc,
      devicePqcSigningKeyService: bobOldSigning,
      remoteDataSource: remote,
      secretStore: bobOldSecrets,
    );
    final aliceCodec = GroupCipherMessageCodec(groupKeyStore: aliceStore);
    final bobOldCodec = GroupCipherMessageCodec(groupKeyStore: bobOldStore);

    final payload = await aliceCodec.encrypt(
      conversation: conversation,
      plaintext: 'legacy group hello',
      usersById: usersById,
    );
    final oldDecrypted = await bobOldCodec.decrypt(
      conversation: conversation,
      payload: payload,
      usersById: usersById,
    );
    expect(oldDecrypted, 'legacy group hello');

    final bobOldRegistry = KeyMaterialRegistry(
      deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
      deviceKeyService: DeviceKeyService(secretStore: bobOldSecrets),
      devicePqcKeyService: bobOldPqc,
      devicePqcSigningKeyService: bobOldSigning,
      secretStore: bobOldSecrets,
    );
    await bobOldRegistry.ensureCurrentKeysetRegistered();
    final backupService = CryptoBackupService(
      keyMaterialRegistry: bobOldRegistry,
      secretStore: bobOldSecrets,
    );
    final blob = await backupService.exportEncryptedBackup(
      const BackupExportRequest(recoveryPassphrase: 'group-pass'),
    );

    final bobNewSecrets = _MemorySecretStore();
    final bobNewRegistry = KeyMaterialRegistry(secretStore: bobNewSecrets);
    await CryptoBackupService(
      keyMaterialRegistry: bobNewRegistry,
      secretStore: bobNewSecrets,
    ).importEncryptedBackup(
      BackupImportRequest(
        recoveryPassphrase: 'group-pass',
        encryptedBlob: blob,
      ),
    );

    final bobNewStore = GroupKeyStore(
      deviceIdentityService: _FakeDeviceIdentityService('bob-new-device'),
      devicePqcKeyService: DevicePqcKeyService(secretStore: bobNewSecrets),
      devicePqcSigningKeyService: DevicePqcSigningKeyService(
        secretStore: bobNewSecrets,
      ),
      remoteDataSource: _FakeChatRemoteDataSource(),
      secretStore: bobNewSecrets,
    );
    final bobNewCodec = GroupCipherMessageCodec(groupKeyStore: bobNewStore);
    final restored = await bobNewCodec.decrypt(
      conversation: conversation,
      payload: payload,
      usersById: usersById,
    );
    expect(restored, 'legacy group hello');
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
  Future<void> deleteAll() async {
    _values.clear();
    _managed.clear();
  }

  @override
  Future<List<String>> listManagedKeys() async => _managed.toList();
}

class _FakeChatRemoteDataSource extends ChatRemoteDataSource {
  _FakeChatRemoteDataSource()
    : super(apiClient: _NoopApiClient());

  String lastKeyId = '';
  final List<ConversationKeyEnvelope> _storedEnvelopes = [];

  @override
  Future<List<ConversationKeyEnvelope>> fetchConversationKeyEnvelopes(
    int conversationId,
  ) async {
    return _storedEnvelopes;
  }

  @override
  Future<void> syncConversationKeyEnvelopes({
    required int conversationId,
    required String keyId,
    required String algorithm,
    required List<ConversationKeyEnvelopeUpload> envelopes,
  }) async {
    lastKeyId = keyId;
    _storedEnvelopes
      ..clear()
      ..addAll(
        envelopes.map(
          (item) => ConversationKeyEnvelope(
            keyId: keyId,
            algorithm: algorithm,
            targetDeviceId: item.targetDeviceId,
            senderDeviceId: 'alice-device',
            wrappedKey: item.wrappedKey,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        ),
      );
  }
}

class _NoopApiClient extends ApiClient {}
