import 'dart:convert';

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
import 'package:pqc_chat_app/features/crypto/chat_crypto_context.dart';
import 'package:pqc_chat_app/features/crypto/chat_cipher_service.dart';
import 'package:pqc_chat_app/features/crypto/durability/crypto_backup_service.dart';
import 'package:pqc_chat_app/features/crypto/durability/crypto_core_facade.dart';
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

  test('private decrypt classification requires backup when historical keyset is absent', () async {
    final aliceSecrets = _MemorySecretStore();
    final bobOldSecrets = _MemorySecretStore();
    final alicePqc = DevicePqcKeyService(secretStore: aliceSecrets);
    final aliceSigning = DevicePqcSigningKeyService(secretStore: aliceSecrets);
    final bobOldPqc = DevicePqcKeyService(secretStore: bobOldSecrets);
    final bobOldSigning = DevicePqcSigningKeyService(secretStore: bobOldSecrets);
    final fixture = await _buildPrivateFixture(
      alicePqc: alicePqc,
      aliceSigning: aliceSigning,
      bobPqc: bobOldPqc,
      bobSigning: bobOldSigning,
      bobDeviceId: 'bob-old-device',
    );

    final payload = await fixture.aliceCodec.encrypt(
      currentUserId: 1,
      conversation: fixture.conversation,
      plaintext: 'restore me later',
      usersById: fixture.usersById,
    );

    final bobNewSecrets = _MemorySecretStore();
    final bobNewCore = _buildCryptoCore(
      deviceId: 'bob-new-device',
      secretStore: bobNewSecrets,
      registry: KeyMaterialRegistry(secretStore: bobNewSecrets),
      remoteDataSource: _FakeChatRemoteDataSource(),
    );

    final outcome = await bobNewCore.classifyFailedDecrypt(payload);
    expect(outcome, isA<DecryptNeedsBackupRestore>());
  });

  test('private decrypt classification reports key missing when unrelated history exists', () async {
    final aliceSecrets = _MemorySecretStore();
    final bobOldSecrets = _MemorySecretStore();
    final alicePqc = DevicePqcKeyService(secretStore: aliceSecrets);
    final aliceSigning = DevicePqcSigningKeyService(secretStore: aliceSecrets);
    final bobOldPqc = DevicePqcKeyService(secretStore: bobOldSecrets);
    final bobOldSigning = DevicePqcSigningKeyService(secretStore: bobOldSecrets);
    final fixture = await _buildPrivateFixture(
      alicePqc: alicePqc,
      aliceSigning: aliceSigning,
      bobPqc: bobOldPqc,
      bobSigning: bobOldSigning,
      bobDeviceId: 'bob-old-device',
    );

    final payload = await fixture.aliceCodec.encrypt(
      currentUserId: 1,
      conversation: fixture.conversation,
      plaintext: 'history from another device',
      usersById: fixture.usersById,
    );

    final unrelatedSecrets = _MemorySecretStore();
    final unrelatedRegistry = KeyMaterialRegistry(
      deviceIdentityService: _FakeDeviceIdentityService('someone-else-device'),
      deviceKeyService: DeviceKeyService(secretStore: unrelatedSecrets),
      devicePqcKeyService: DevicePqcKeyService(secretStore: unrelatedSecrets),
      devicePqcSigningKeyService: DevicePqcSigningKeyService(
        secretStore: unrelatedSecrets,
      ),
      secretStore: unrelatedSecrets,
    );
    await unrelatedRegistry.ensureCurrentKeysetRegistered();

    final bobNewSecrets = _MemorySecretStore();
    final bobNewRegistry = KeyMaterialRegistry(secretStore: bobNewSecrets);
    await bobNewRegistry.importKeysets(await unrelatedRegistry.readAllKeysets());

    final bobNewCore = _buildCryptoCore(
      deviceId: 'bob-new-device',
      secretStore: bobNewSecrets,
      registry: bobNewRegistry,
      remoteDataSource: _FakeChatRemoteDataSource(),
    );

    final outcome = await bobNewCore.classifyFailedDecrypt(payload);
    expect(outcome, isA<DecryptKeyMissing>());
  });

  test('tampered private payload is classified as corrupted when matching history exists', () async {
    final aliceSecrets = _MemorySecretStore();
    final bobOldSecrets = _MemorySecretStore();
    final alicePqc = DevicePqcKeyService(secretStore: aliceSecrets);
    final aliceSigning = DevicePqcSigningKeyService(secretStore: aliceSecrets);
    final bobOldPqc = DevicePqcKeyService(secretStore: bobOldSecrets);
    final bobOldSigning = DevicePqcSigningKeyService(secretStore: bobOldSecrets);
    final bobOldRegistry = KeyMaterialRegistry(
      deviceIdentityService: _FakeDeviceIdentityService('bob-old-device'),
      deviceKeyService: DeviceKeyService(secretStore: bobOldSecrets),
      devicePqcKeyService: bobOldPqc,
      devicePqcSigningKeyService: bobOldSigning,
      secretStore: bobOldSecrets,
    );
    await bobOldRegistry.ensureCurrentKeysetRegistered();

    final fixture = await _buildPrivateFixture(
      alicePqc: alicePqc,
      aliceSigning: aliceSigning,
      bobPqc: bobOldPqc,
      bobSigning: bobOldSigning,
      bobDeviceId: 'bob-old-device',
    );
    final payload = await fixture.aliceCodec.encrypt(
      currentUserId: 1,
      conversation: fixture.conversation,
      plaintext: 'please survive tamper checks',
      usersById: fixture.usersById,
    );

    final backup = await CryptoBackupService(
      keyMaterialRegistry: bobOldRegistry,
      secretStore: bobOldSecrets,
    ).exportEncryptedBackup(
      const BackupExportRequest(recoveryPassphrase: 'tamper-pass'),
    );

    final bobNewSecrets = _MemorySecretStore();
    final bobNewRegistry = KeyMaterialRegistry(secretStore: bobNewSecrets);
    await CryptoBackupService(
      keyMaterialRegistry: bobNewRegistry,
      secretStore: bobNewSecrets,
    ).importEncryptedBackup(
      BackupImportRequest(
        recoveryPassphrase: 'tamper-pass',
        encryptedBlob: backup,
      ),
    );

    final parts = payload.split(':');
    parts[12] = base64Encode(
      List<int>.from(base64Decode(parts[12]))..[0] ^= 0x01,
    );
    final tamperedPayload = parts.join(':');

    final bobNewCore = _buildCryptoCore(
      deviceId: 'bob-new-device',
      secretStore: bobNewSecrets,
      registry: bobNewRegistry,
      remoteDataSource: _FakeChatRemoteDataSource(),
    );
    final outcome = await bobNewCore.classifyFailedDecrypt(tamperedPayload);
    expect(outcome, isA<DecryptCorruptedPayload>());
  });

  test('restored historical private keysets decrypt mixed history after multiple rotations', () async {
    final aliceSecrets = _MemorySecretStore();
    final alicePqc = DevicePqcKeyService(secretStore: aliceSecrets);
    final aliceSigning = DevicePqcSigningKeyService(secretStore: aliceSecrets);

    final oldBobFixtures =
        <({
          String backup,
          String deviceId,
          List<String> payloads,
          Map<int, AppUser> usersById,
        })>[];
    for (final deviceId in ['bob-old-1', 'bob-old-2', 'bob-old-3']) {
      final bobSecrets = _MemorySecretStore();
      final bobPqc = DevicePqcKeyService(secretStore: bobSecrets);
      final bobSigning = DevicePqcSigningKeyService(secretStore: bobSecrets);
      final bobRegistry = KeyMaterialRegistry(
        deviceIdentityService: _FakeDeviceIdentityService(deviceId),
        deviceKeyService: DeviceKeyService(secretStore: bobSecrets),
        devicePqcKeyService: bobPqc,
        devicePqcSigningKeyService: bobSigning,
        secretStore: bobSecrets,
      );
      await bobRegistry.ensureCurrentKeysetRegistered();
      final fixture = await _buildPrivateFixture(
        alicePqc: alicePqc,
        aliceSigning: aliceSigning,
        bobPqc: bobPqc,
        bobSigning: bobSigning,
        bobDeviceId: deviceId,
      );
      final payloads = <String>[];
      for (var index = 0; index < 6; index++) {
        payloads.add(
          await fixture.aliceCodec.encrypt(
            currentUserId: 1,
            conversation: fixture.conversation,
            plaintext: 'history-$deviceId-$index',
            usersById: fixture.usersById,
          ),
        );
      }
      final backup = await CryptoBackupService(
        keyMaterialRegistry: bobRegistry,
        secretStore: bobSecrets,
      ).exportEncryptedBackup(
        BackupExportRequest(recoveryPassphrase: 'restore-$deviceId'),
      );
      oldBobFixtures.add((
        backup: backup,
        deviceId: deviceId,
        payloads: payloads,
        usersById: fixture.usersById,
      ));
    }

    final bobNewSecrets = _MemorySecretStore();
    final bobNewRegistry = KeyMaterialRegistry(secretStore: bobNewSecrets);
    final importService = CryptoBackupService(
      keyMaterialRegistry: bobNewRegistry,
      secretStore: bobNewSecrets,
    );
    for (final fixture in oldBobFixtures) {
      await importService.importEncryptedBackup(
        BackupImportRequest(
          recoveryPassphrase: 'restore-${fixture.deviceId}',
          encryptedBlob: fixture.backup,
        ),
      );
    }

    final bobNewCodec = PqcPrivateMessageCodec(
      deviceIdentityService: _FakeDeviceIdentityService('bob-fresh-device'),
      devicePqcKeyService: DevicePqcKeyService(secretStore: bobNewSecrets),
      devicePqcSigningKeyService: DevicePqcSigningKeyService(
        secretStore: bobNewSecrets,
      ),
      keyMaterialRegistry: bobNewRegistry,
    );

    for (final fixture in oldBobFixtures) {
      for (var index = 0; index < fixture.payloads.length; index++) {
        final plaintext = await bobNewCodec.decrypt(
          currentUserId: 2,
          conversation: _privateConversation,
          payload: fixture.payloads[index],
          usersById: fixture.usersById,
        );
        expect(plaintext, 'history-${fixture.deviceId}-$index');
      }
    }
    final historicalCheck = await bobNewRegistry.historicalDecryptCheck();
    expect(historicalCheck.availableKeysets, greaterThanOrEqualTo(3));
  });

  test('restored group history survives multiple rekeys after reinstall', () async {
    final aliceSecrets = _MemorySecretStore();
    final bobOldSecrets = _MemorySecretStore();
    final charlieSecrets = _MemorySecretStore();
    final alicePqc = DevicePqcKeyService(secretStore: aliceSecrets);
    final bobOldPqc = DevicePqcKeyService(secretStore: bobOldSecrets);
    final charliePqc = DevicePqcKeyService(secretStore: charlieSecrets);
    final aliceSigning = DevicePqcSigningKeyService(secretStore: aliceSecrets);
    final bobOldSigning = DevicePqcSigningKeyService(secretStore: bobOldSecrets);
    final charlieSigning = DevicePqcSigningKeyService(secretStore: charlieSecrets);
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

    final payloads = <String>[];
    final conversations = <Conversation>[];
    final usersVariants = <Map<int, AppUser>>[];
    for (var rotation = 0; rotation < 3; rotation++) {
      final includeCharlie = rotation.isOdd;
      final conversation = Conversation(
        id: 19,
        type: 'group',
        title: 'General',
        participantIds: includeCharlie ? const [1, 2, 3] : const [1, 2],
        lastMessagePreview: '',
        updatedAt: DateTime.parse('2026-07-11T00:00:00Z'),
      );
      final usersById = await _buildGroupUsers(
        alicePqc: alicePqc,
        aliceSigning: aliceSigning,
        bobPqc: bobOldPqc,
        bobSigning: bobOldSigning,
        charliePqc: includeCharlie ? charliePqc : null,
        charlieSigning: includeCharlie ? charlieSigning : null,
      );
      usersVariants.add(usersById);
      conversations.add(conversation);
      for (var index = 0; index < 4; index++) {
        final plaintext = 'group-r$rotation-m$index';
        final payload = await aliceCodec.encrypt(
          conversation: conversation,
          plaintext: plaintext,
          usersById: usersById,
        );
        expect(
          await bobOldCodec.decrypt(
            conversation: conversation,
            payload: payload,
            usersById: usersById,
          ),
          plaintext,
        );
        payloads.add(payload);
      }
    }

    final bobOldRegistry = KeyMaterialRegistry(
      deviceIdentityService: _FakeDeviceIdentityService('bob-device'),
      deviceKeyService: DeviceKeyService(secretStore: bobOldSecrets),
      devicePqcKeyService: bobOldPqc,
      devicePqcSigningKeyService: bobOldSigning,
      secretStore: bobOldSecrets,
    );
    await bobOldRegistry.ensureCurrentKeysetRegistered();
    final backup = await CryptoBackupService(
      keyMaterialRegistry: bobOldRegistry,
      secretStore: bobOldSecrets,
    ).exportEncryptedBackup(
      const BackupExportRequest(recoveryPassphrase: 'group-history-pass'),
    );

    final bobNewSecrets = _MemorySecretStore();
    final bobNewRegistry = KeyMaterialRegistry(secretStore: bobNewSecrets);
    await CryptoBackupService(
      keyMaterialRegistry: bobNewRegistry,
      secretStore: bobNewSecrets,
    ).importEncryptedBackup(
      BackupImportRequest(
        recoveryPassphrase: 'group-history-pass',
        encryptedBlob: backup,
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

    var payloadIndex = 0;
    for (var rotation = 0; rotation < usersVariants.length; rotation++) {
      for (var index = 0; index < 4; index++) {
        final plaintext = await bobNewCodec.decrypt(
          conversation: conversations[rotation],
          payload: payloads[payloadIndex],
          usersById: usersVariants[rotation],
        );
        expect(plaintext, 'group-r$rotation-m$index');
        payloadIndex++;
      }
    }
  });
}

final _privateConversation = Conversation(
  id: 77,
  type: 'private',
  title: '',
  participantIds: const [1, 2],
  lastMessagePreview: '',
  updatedAt: DateTime.parse('2026-07-11T00:00:00Z'),
);

Future<_PrivateFixture> _buildPrivateFixture({
  required DevicePqcKeyService alicePqc,
  required DevicePqcSigningKeyService aliceSigning,
  required DevicePqcKeyService bobPqc,
  required DevicePqcSigningKeyService bobSigning,
  required String bobDeviceId,
}) async {
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
          deviceId: bobDeviceId,
          deviceName: 'Bob',
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

  return _PrivateFixture(
    conversation: _privateConversation,
    usersById: usersById,
    aliceCodec: PqcPrivateMessageCodec(
      deviceIdentityService: _FakeDeviceIdentityService('alice-device'),
      devicePqcKeyService: alicePqc,
      devicePqcSigningKeyService: aliceSigning,
    ),
  );
}

Future<Map<int, AppUser>> _buildGroupUsers({
  required DevicePqcKeyService alicePqc,
  required DevicePqcSigningKeyService aliceSigning,
  required DevicePqcKeyService bobPqc,
  required DevicePqcSigningKeyService bobSigning,
  DevicePqcKeyService? charliePqc,
  DevicePqcSigningKeyService? charlieSigning,
}) async {
  final alicePqcMaterial = await alicePqc.getOrCreateKeyMaterial();
  final bobPqcMaterial = await bobPqc.getOrCreateKeyMaterial();
  final aliceSigningMaterial = await aliceSigning.getOrCreateKeyMaterial();
  final bobSigningMaterial = await bobSigning.getOrCreateKeyMaterial();
  final users = <int, AppUser>{
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
          pqcPublicKey: bobPqcMaterial.publicKey,
          pqcAlgorithm: bobPqcMaterial.algorithm,
          pqcSigningPublicKey: bobSigningMaterial.publicKey,
          pqcSigningAlgorithm: bobSigningMaterial.algorithm,
        ),
      ],
    ),
  };

  if (charliePqc != null && charlieSigning != null) {
    final charliePqcMaterial = await charliePqc.getOrCreateKeyMaterial();
    final charlieSigningMaterial = await charlieSigning.getOrCreateKeyMaterial();
    users[3] = AppUser(
      id: 3,
      username: 'charlie',
      displayName: 'Charlie',
      devices: [
        AppUserDevice(
          deviceId: 'charlie-device',
          deviceName: 'Charlie',
          platform: 'ios',
          identityPublicKey: '',
          keyAlgorithm: '',
          pqcPublicKey: charliePqcMaterial.publicKey,
          pqcAlgorithm: charliePqcMaterial.algorithm,
          pqcSigningPublicKey: charlieSigningMaterial.publicKey,
          pqcSigningAlgorithm: charlieSigningMaterial.algorithm,
        ),
      ],
    );
  }

  return users;
}

CryptoCoreFacade _buildCryptoCore({
  required String deviceId,
  required _MemorySecretStore secretStore,
  required KeyMaterialRegistry registry,
  required ChatRemoteDataSource remoteDataSource,
}) {
  final devicePqc = DevicePqcKeyService(secretStore: secretStore);
  final deviceSigning = DevicePqcSigningKeyService(secretStore: secretStore);
  final groupKeyStore = GroupKeyStore(
    deviceIdentityService: _FakeDeviceIdentityService(deviceId),
    devicePqcKeyService: devicePqc,
    devicePqcSigningKeyService: deviceSigning,
    remoteDataSource: remoteDataSource,
    secretStore: secretStore,
  );
  return CryptoCoreFacade(
    cipherService: _NoopChatCipherService(),
    groupKeyStore: groupKeyStore,
    keyMaterialRegistry: registry,
    backupService: CryptoBackupService(
      keyMaterialRegistry: registry,
      secretStore: secretStore,
    ),
  );
}

class _PrivateFixture {
  const _PrivateFixture({
    required this.conversation,
    required this.usersById,
    required this.aliceCodec,
  });

  final Conversation conversation;
  final Map<int, AppUser> usersById;
  final PqcPrivateMessageCodec aliceCodec;
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

class _NoopChatCipherService implements ChatCipherService {
  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async => payload;

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) async => plaintext;
}
