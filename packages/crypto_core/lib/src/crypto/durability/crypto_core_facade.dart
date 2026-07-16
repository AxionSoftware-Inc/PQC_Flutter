import 'dart:convert';

import '../chat_cipher_service.dart';
import '../group_key_store.dart';
import '../message_codec.dart';
import '../../core/storage/local_secret_store.dart';
import 'crypto_backup_service.dart';
import 'conversation_epoch_key_store.dart';
import 'crypto_durability_models.dart';
import 'key_material_registry.dart';
import 'key_continuity_guard.dart';
import 'crypto_health_monitor.dart';
import 'payload_format_registry.dart';
import 'protocol_version_manager.dart';
import '../v3/v3_envelope.dart';

class CryptoCoreFacade {
  CryptoCoreFacade({
    required this.cipherService,
    required this.groupKeyStore,
    required this.keyMaterialRegistry,
    required this.backupService,
    ConversationEpochKeyStore? conversationEpochKeyStore,
    LocalSecretStore? secretStore,
    PayloadFormatRegistry? payloadFormatRegistry,
  }) : conversationEpochKeyStore =
           conversationEpochKeyStore ?? ConversationEpochKeyStore(),
       _secretStore = secretStore ?? LocalSecretStore(),
       _payloadFormatRegistry =
           payloadFormatRegistry ?? PayloadFormatRegistry(),
       protocolVersionManager = ProtocolVersionManager(
         registry: payloadFormatRegistry,
       );

  final ChatCipherService cipherService;
  final GroupKeyStore groupKeyStore;
  final KeyMaterialRegistry keyMaterialRegistry;
  final CryptoBackupService backupService;
  final ConversationEpochKeyStore conversationEpochKeyStore;
  final LocalSecretStore _secretStore;
  final PayloadFormatRegistry _payloadFormatRegistry;
  final ProtocolVersionManager protocolVersionManager;

  late final KeyContinuityGuard keyContinuityGuard = KeyContinuityGuard(
    registry: keyMaterialRegistry,
  );
  late final CryptoHealthMonitor healthMonitor = CryptoHealthMonitor(
    registry: keyMaterialRegistry,
  );

  List<PayloadFormatDescriptor> get supportedFormats =>
      _payloadFormatRegistry.descriptors;

  /// The active writer is selected from the registry, never inferred from a
  /// decoder class. This is the client side of the client/server protocol
  /// handshake.
  String activeMessageWriterPrefix({required bool isGroup}) {
    return protocolVersionManager
        .activeWriter(
          isGroup ? PayloadKind.groupMessage : PayloadKind.privateMessage,
        )
        .prefix;
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
    return keyContinuityGuard.ensureCurrentPreservingHistory().then((_) {});
  }

  Future<CryptoHealthSnapshot> healthCheck() => healthMonitor.check();

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
            key == 'crypto_keyset_registry_pending_v1' ||
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
    return protocolVersionManager.readerForPayload(payload);
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
    final isV2 = payload.startsWith('${PqcPrivateMessageCodec.prefix}:');
    final isV3 = payload.startsWith('pqc:v3:');
    if (!isV2 && !isV3) {
      return const DeviceKeyMatch(
        isKnownFormat: false,
        hasMatchingKeyset: false,
      );
    }
    try {
      if (isV3) {
        final envelope = V3Envelope.decode(payload);
        final keysets = await keyMaterialRegistry
            .readHistoricalDecryptKeysets();
        final hasMatchingKeyset = envelope.wraps.any(
          (wrap) => keysets.any(
            (keyset) =>
                keyset.keysetId == wrap.keysetId &&
                keyset.deviceId == wrap.deviceId,
          ),
        );
        return DeviceKeyMatch(
          isKnownFormat: true,
          hasMatchingKeyset: hasMatchingKeyset,
          senderDeviceId: envelope.senderDeviceId,
        );
      }
      final encoded = payload.substring(
        PqcPrivateMessageCodec.prefix.length + 1,
      );
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
