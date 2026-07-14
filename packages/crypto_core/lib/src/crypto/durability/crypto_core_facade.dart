import 'dart:convert';

import '../chat_cipher_service.dart';
import '../group_key_store.dart';
import '../message_codec.dart';
import '../../core/storage/local_secret_store.dart';
import 'crypto_backup_service.dart';
import 'conversation_epoch_key_store.dart';
import 'crypto_durability_models.dart';
import 'key_material_registry.dart';
import 'payload_format_registry.dart';
import '../../engine_version_manager.dart';

class CryptoCoreFacade {
  CryptoCoreFacade({
    required this.cipherService,
    required this.groupKeyStore,
    required this.keyMaterialRegistry,
    required this.backupService,
    ConversationEpochKeyStore? conversationEpochKeyStore,
    LocalSecretStore? secretStore,
    PayloadFormatRegistry? payloadFormatRegistry,
    EngineVersionManager? versionManager,
  }) : conversationEpochKeyStore =
           conversationEpochKeyStore ?? ConversationEpochKeyStore(),
       _secretStore = secretStore ?? LocalSecretStore(),
       _versionManager =
           versionManager ??
           EngineVersionManager(payloadRegistry: payloadFormatRegistry);

  final ChatCipherService cipherService;
  final GroupKeyStore groupKeyStore;
  final KeyMaterialRegistry keyMaterialRegistry;
  final CryptoBackupService backupService;
  final ConversationEpochKeyStore conversationEpochKeyStore;
  final LocalSecretStore _secretStore;
  final EngineVersionManager _versionManager;

  String get engineVersion => _versionManager.activeEngineVersion;

  List<PayloadFormatDescriptor> get supportedFormats =>
      _versionManager.readableFormats;

  /// The active writer is selected from the registry, never inferred from a
  /// decoder class. This is the client side of the client/server protocol
  /// handshake.
  String activeMessageWriterPrefix({required bool isGroup}) {
    return _versionManager.activeWriterPrefix(isGroup: isGroup);
  }

  void assertRemoteSupportsActiveMessageWriter({
    required bool isGroup,
    required Iterable<String> remotePrefixes,
  }) {
    final writer = activeMessageWriterPrefix(isGroup: isGroup);
    if (!remotePrefixes.contains(writer)) {
      throw StateError(
        'Server does not support the active crypto protocol $writer. '
        'Update the server before sending encrypted messages.',
      );
    }
  }

  Future<void> initialize() {
    _versionManager.validate();
    return keyMaterialRegistry.ensureCurrentKeysetRegistered();
  }

  /// Account identity is injected by the app; the core is independent of its
  /// OIDC/Google provider. A different account cannot reuse local recovery
  /// material from the prior account.
  Future<void> activateAccount(String accountNamespace) async {
    if (accountNamespace.trim().isEmpty) {
      throw ArgumentError.value(accountNamespace, 'accountNamespace');
    }
    const markerKey = 'crypto_core_active_account_namespace_v2';
    final previous = await _secretStore.read(markerKey);
    if (previous != null &&
        previous.isNotEmpty &&
        previous != accountNamespace) {
      for (final key in await _secretStore.listManagedKeys()) {
        if (key == 'crypto_keyset_registry_v1' ||
            key.startsWith('crypto_keyset_entry_v1') ||
            key.startsWith('group_secret_key_') ||
            key.startsWith('group_participant_signature_') ||
            key.startsWith('attachment_conversation_epoch_v2_')) {
          await _secretStore.delete(key);
        }
      }
    }
    await _secretStore.write(key: markerKey, value: accountNamespace);
  }

  Future<String> exportEncryptedBackup(BackupExportRequest request) {
    return backupService.exportEncryptedBackup(request);
  }

  Future<void> importEncryptedBackup(BackupImportRequest request) {
    return backupService.importEncryptedBackup(request);
  }

  Future<String> exportEnterpriseRecoveryManifest() {
    return backupService.exportEnterpriseRecoveryManifest();
  }

  Future<void> importEnterpriseRecoveryManifest(String payload) {
    return backupService.importEnterpriseRecoveryManifest(payload);
  }

  Future<HistoricalDecryptCheck> historicalDecryptCheck() {
    return keyMaterialRegistry.historicalDecryptCheck();
  }

  PayloadFormatDescriptor? describePayload(String payload) {
    return _versionManager.describe(payload);
  }

  bool privatePayloadMayNeedHistoricalKey(String payload) {
    return describePayload(payload)?.payloadKind == PayloadKind.privateMessage;
  }

  bool groupPayloadMayNeedHistoricalKey(String payload) {
    return describePayload(payload)?.payloadKind == PayloadKind.groupMessage;
  }

  Future<DeviceKeyMatch> evaluatePrivatePayloadLocalKeyMatch(
    String payload,
  ) async {
    if (!payload.startsWith('${PqcPrivateMessageCodec.prefix}:')) {
      return const DeviceKeyMatch(
        isKnownFormat: false,
        hasMatchingKeyset: false,
      );
    }
    final encoded = payload.substring(PqcPrivateMessageCodec.prefix.length + 1);
    try {
      final padded = encoded.padRight(
        encoded.length + ((4 - encoded.length % 4) % 4),
        '=',
      );
      final document =
          jsonDecode(utf8.decode(base64Url.decode(padded)))
              as Map<String, dynamic>;
      final senderDeviceId = document['sender_device_id'] as String? ?? '';
      final wraps = (document['wraps'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .toList();
      final keysets = await keyMaterialRegistry.readHistoricalDecryptKeysets();
      final hasMatchingKeyset = wraps.any((wrap) {
        final targetKeysetId = wrap['target_keyset_id'] as String? ?? '';
        final targetDeviceId = wrap['target_device_id'] as String? ?? '';
        return keysets.any(
          (keyset) =>
              keyset.keysetId == targetKeysetId &&
              keyset.deviceId == targetDeviceId,
        );
      });
      return DeviceKeyMatch(
        isKnownFormat: document['protocol_version'] == 2,
        hasMatchingKeyset: hasMatchingKeyset,
        senderDeviceId: senderDeviceId,
      );
    } catch (_) {
      return const DeviceKeyMatch(
        isKnownFormat: true,
        hasMatchingKeyset: false,
      );
    }
  }

  Future<DecryptionOutcome> classifyFailedDecrypt(String payload) async {
    final format = describePayload(payload);
    if (format == null) {
      return DecryptFormatUnsupported(payload: payload);
    }
    if (format.payloadKind == PayloadKind.privateMessage) {
      final match = await evaluatePrivatePayloadLocalKeyMatch(payload);
      if (!match.isKnownFormat) {
        return DecryptFormatUnsupported(payload: payload);
      }
      if (match.hasMatchingKeyset) {
        return DecryptCorruptedPayload(format: format);
      }
      final historical = await historicalDecryptCheck();
      if (!historical.hasHistoricalCapability) {
        return DecryptNeedsBackupRestore(format: format);
      }
      return DecryptKeyMissing(format: format);
    }
    final historical = await historicalDecryptCheck();
    if (!historical.hasHistoricalCapability) {
      return DecryptNeedsBackupRestore(format: format);
    }
    return DecryptKeyMissing(format: format);
  }
}

class DeviceKeyMatch {
  const DeviceKeyMatch({
    required this.isKnownFormat,
    required this.hasMatchingKeyset,
    this.senderDeviceId,
    this.targetDeviceId,
  });

  final bool isKnownFormat;
  final bool hasMatchingKeyset;
  final String? senderDeviceId;
  final String? targetDeviceId;
}
