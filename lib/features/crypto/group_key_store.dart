// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../../core/device/device_identity_service.dart';
import '../../core/device/device_key_service.dart';
import '../../core/models/app_user.dart';
import '../../core/models/conversation.dart';
import '../../core/models/conversation_key_envelope.dart';
import '../../core/storage/local_secret_store.dart';
import '../chat/data/chat_remote_data_source.dart';
import 'chat_crypto_exceptions.dart';

class GroupKeyMaterial {
  const GroupKeyMaterial({required this.keyId, required this.secretKeyBytes});

  final String keyId;
  final List<int> secretKeyBytes;
}

abstract class GroupKeyProvider {
  Future<GroupKeyMaterial> getOrCreateKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  });

  Future<GroupKeyMaterial?> getExistingKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    String? requestedKeyId,
  });
}

class GroupKeyStore implements GroupKeyProvider {
  GroupKeyStore({
    required DeviceIdentityService deviceIdentityService,
    required DeviceKeyService deviceKeyService,
    required ChatRemoteDataSource remoteDataSource,
    LocalSecretStore? secretStore,
    X25519? keyExchange,
    Hkdf? hkdf,
    AesGcm? cipher,
    Uuid? uuid,
  }) : _deviceIdentityService = deviceIdentityService,
       _deviceKeyService = deviceKeyService,
       _remoteDataSource = remoteDataSource,
       _secretStore = secretStore ?? LocalSecretStore(),
       _keyExchange = keyExchange ?? X25519(),
       _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
       _cipher = cipher ?? AesGcm.with256bits(),
       _uuid = uuid ?? const Uuid();

  static const _localKeyPrefix = 'group_secret_key';
  static const _participantSignaturePrefix = 'group_participant_signature';
  static final _random = Random.secure();

  final DeviceIdentityService _deviceIdentityService;
  final DeviceKeyService _deviceKeyService;
  final ChatRemoteDataSource _remoteDataSource;
  final LocalSecretStore _secretStore;
  final X25519 _keyExchange;
  final Hkdf _hkdf;
  final AesGcm _cipher;
  final Uuid _uuid;

  @override
  Future<GroupKeyMaterial> getOrCreateKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    final targetDevices = _resolveTargetDevices(
      conversation: conversation,
      usersById: usersById,
    );
    final currentSignature = _participantSignature(
      conversation: conversation,
      usersById: usersById,
    );
    final existing = await getExistingKey(
      conversation: conversation,
      usersById: usersById,
    );
    final savedSignature = await _secretStore.read(
      _participantSignatureStorageKey(conversation.id),
    );
    if (existing != null && savedSignature == currentSignature) {
      return existing;
    }

    final deviceIdentity = await _deviceIdentityService.getIdentity();
    final localKeyPair = await _deviceKeyService.getIdentityKeyPair();
    final keyId = _uuid.v4();
    final secretKeyBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final envelopes = <ConversationKeyEnvelopeUpload>[];

    for (final device in targetDevices) {
      envelopes.add(
        ConversationKeyEnvelopeUpload(
          targetDeviceId: device.deviceId,
          wrappedKey: await _wrapGroupKeyForDevice(
            conversation: conversation,
            keyId: keyId,
            senderDeviceId: deviceIdentity.id,
            targetDevice: device,
            localKeyPair: localKeyPair,
            secretKeyBytes: secretKeyBytes,
          ),
        ),
      );
    }

    if (envelopes.length != targetDevices.length) {
      throw ChatEncryptionException(
        'Group key distribution incomplete. Retry after all participants re-open the app.',
      );
    }

    await _remoteDataSource.syncConversationKeyEnvelopes(
      conversationId: conversation.id,
      keyId: keyId,
      algorithm: 'group-x25519-aesgcm-v1',
      envelopes: envelopes,
    );
    await _saveLocalKey(
      conversationId: conversation.id,
      keyId: keyId,
      secretKeyBytes: secretKeyBytes,
    );
    await _secretStore.write(
      key: _participantSignatureStorageKey(conversation.id),
      value: currentSignature,
    );

    return GroupKeyMaterial(keyId: keyId, secretKeyBytes: secretKeyBytes);
  }

  @override
  Future<GroupKeyMaterial?> getExistingKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    String? requestedKeyId,
  }) async {
    final deviceIdentity = await _deviceIdentityService.getIdentity();
    final envelopes = await _remoteDataSource.fetchConversationKeyEnvelopes(
      conversation.id,
    );
    final relevantEnvelopes = envelopes.where((item) {
      if (item.targetDeviceId != deviceIdentity.id) {
        return false;
      }
      if (requestedKeyId == null) {
        return true;
      }
      return item.keyId == requestedKeyId;
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    for (final envelope in relevantEnvelopes) {
      final cached = await _readLocalKey(
        conversationId: conversation.id,
        keyId: envelope.keyId,
      );
      if (cached != null) {
        return GroupKeyMaterial(keyId: envelope.keyId, secretKeyBytes: cached);
      }

      final senderDevice = _findDeviceById(
        usersById: usersById,
        deviceId: envelope.senderDeviceId,
      );
      if (senderDevice == null) {
        continue;
      }
      final secretKeyBytes = await _unwrapGroupKeyFromEnvelope(
        conversation: conversation,
        keyId: envelope.keyId,
        senderDevice: senderDevice,
        targetDeviceId: envelope.targetDeviceId,
        wrappedKey: envelope.wrappedKey,
      );
      if (secretKeyBytes == null) {
        continue;
      }

      await _saveLocalKey(
        conversationId: conversation.id,
        keyId: envelope.keyId,
        secretKeyBytes: secretKeyBytes,
      );
      return GroupKeyMaterial(
        keyId: envelope.keyId,
        secretKeyBytes: secretKeyBytes,
      );
    }

    return null;
  }

  AppUserDevice? _findDeviceById({
    required Map<int, AppUser> usersById,
    required String deviceId,
  }) {
    for (final user in usersById.values) {
      for (final device in user.devices) {
        if (device.deviceId == deviceId) {
          return device;
        }
      }
    }
    return null;
  }

  Future<String> _wrapGroupKeyForDevice({
    required Conversation conversation,
    required String keyId,
    required String senderDeviceId,
    required AppUserDevice targetDevice,
    required SimpleKeyPair localKeyPair,
    required List<int> secretKeyBytes,
  }) async {
    final wrappingKey = await _deriveWrappingKey(
      localKeyPair: localKeyPair,
      remotePublicKey: SimplePublicKey(
        base64Decode(targetDevice.identityPublicKey),
        type: KeyPairType.x25519,
      ),
      info:
          '${conversation.id}|$keyId|$senderDeviceId|${targetDevice.deviceId}',
    );
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _cipher.encrypt(
      secretKeyBytes,
      secretKey: wrappingKey,
      nonce: nonce,
    );
    return [
      'group-wrap:v1',
      base64Encode(secretBox.nonce),
      base64Encode(secretBox.cipherText),
      base64Encode(secretBox.mac.bytes),
    ].join(':');
  }

  Future<List<int>?> _unwrapGroupKeyFromEnvelope({
    required Conversation conversation,
    required String keyId,
    required AppUserDevice senderDevice,
    required String targetDeviceId,
    required String wrappedKey,
  }) async {
    try {
      if (!wrappedKey.startsWith('group-wrap:v1:')) {
        return null;
      }

      final parts = wrappedKey.substring('group-wrap:v1:'.length).split(':');
      if (parts.length != 3) {
        return null;
      }

      final localKeyPair = await _deviceKeyService.getIdentityKeyPair();
      final wrappingKey = await _deriveWrappingKey(
        localKeyPair: localKeyPair,
        remotePublicKey: SimplePublicKey(
          base64Decode(senderDevice.identityPublicKey),
          type: KeyPairType.x25519,
        ),
        info:
            '${conversation.id}|$keyId|${senderDevice.deviceId}|$targetDeviceId',
      );
      final secretBytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(parts[1]),
          nonce: base64Decode(parts[0]),
          mac: Mac(base64Decode(parts[2])),
        ),
        secretKey: wrappingKey,
      );
      return secretBytes;
    } catch (_) {
      return null;
    }
  }

  Future<SecretKey> _deriveWrappingKey({
    required SimpleKeyPair localKeyPair,
    required SimplePublicKey remotePublicKey,
    required String info,
  }) async {
    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );
    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(info),
      info: utf8.encode('pqc-chat-group-key-wrap'),
    );
  }

  Future<void> _saveLocalKey({
    required int conversationId,
    required String keyId,
    required List<int> secretKeyBytes,
  }) {
    return _secretStore.write(
      key: _localStorageKey(conversationId: conversationId, keyId: keyId),
      value: base64Encode(secretKeyBytes),
    );
  }

  Future<List<int>?> _readLocalKey({
    required int conversationId,
    required String keyId,
  }) async {
    final value = await _secretStore.read(
      _localStorageKey(conversationId: conversationId, keyId: keyId),
    );
    if (value == null || value.isEmpty) {
      return null;
    }
    return base64Decode(value);
  }

  String _localStorageKey({
    required int conversationId,
    required String keyId,
  }) {
    return '${_localKeyPrefix}_${conversationId}_$keyId';
  }

  String _participantSignatureStorageKey(int conversationId) {
    return '${_participantSignaturePrefix}_$conversationId';
  }

  String _participantSignature({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    final entries = <String>[];
    final participantIds = [...conversation.participantIds]..sort();
    for (final userId in participantIds) {
      final user = usersById[userId];
      if (user == null) {
        entries.add('$userId:missing');
        continue;
      }
      final devices =
          user.usableX25519Devices
              .map((item) => '${item.deviceId}:${item.identityPublicKey}')
              .toList()
            ..sort();
      if (devices.isEmpty) {
        entries.add('$userId:none');
        continue;
      }
      entries.add('$userId:${devices.join("|")}');
    }
    return entries.join('||');
  }

  List<AppUserDevice> _resolveTargetDevices({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    final targetDevices = <AppUserDevice>[];
    final missingUsers = <String>[];

    for (final userId in conversation.participantIds) {
      final user = usersById[userId];
      if (user == null) {
        missingUsers.add('user-$userId');
        continue;
      }

      final usableDevices = user.usableX25519Devices;
      if (usableDevices.isEmpty) {
        missingUsers.add(user.displayName);
        continue;
      }

      targetDevices.addAll(usableDevices);
    }

    if (missingUsers.isNotEmpty) {
      throw ChatEncryptionException(
        'Group chat ready emas. Key yoq participantlar: ${missingUsers.join(", ")}.',
      );
    }

    if (targetDevices.isEmpty) {
      throw ChatEncryptionException('Groupda usable device key topilmadi.');
    }

    return targetDevices;
  }
}
