import '../chat_cipher_service.dart';
import '../group_key_store.dart';
import '../message_codec.dart';
import 'crypto_backup_service.dart';
import 'crypto_durability_models.dart';
import 'key_material_registry.dart';
import 'payload_format_registry.dart';

class CryptoCoreFacade {
  CryptoCoreFacade({
    required this.cipherService,
    required this.groupKeyStore,
    required this.keyMaterialRegistry,
    required this.backupService,
    PayloadFormatRegistry? payloadFormatRegistry,
  }) : _payloadFormatRegistry =
           payloadFormatRegistry ?? PayloadFormatRegistry();

  final ChatCipherService cipherService;
  final GroupKeyStore groupKeyStore;
  final KeyMaterialRegistry keyMaterialRegistry;
  final CryptoBackupService backupService;
  final PayloadFormatRegistry _payloadFormatRegistry;

  List<PayloadFormatDescriptor> get supportedFormats =>
      _payloadFormatRegistry.descriptors;

  Future<void> initialize() {
    return keyMaterialRegistry.ensureCurrentKeysetRegistered();
  }

  Future<String> exportEncryptedBackup(BackupExportRequest request) {
    return backupService.exportEncryptedBackup(request);
  }

  Future<void> importEncryptedBackup(BackupImportRequest request) {
    return backupService.importEncryptedBackup(request);
  }

  Future<HistoricalDecryptCheck> historicalDecryptCheck() {
    return keyMaterialRegistry.historicalDecryptCheck();
  }

  PayloadFormatDescriptor? describePayload(String payload) {
    return _payloadFormatRegistry.describe(payload);
  }

  bool privatePayloadMayNeedHistoricalKey(String payload) {
    if (!payload.startsWith('${PqcPrivateMessageCodec.prefix}:')) {
      return false;
    }
    return true;
  }

  bool groupPayloadMayNeedHistoricalKey(String payload) {
    return payload.startsWith('${GroupCipherMessageCodec.prefix}:');
  }

  Future<DeviceKeyMatch> evaluatePrivatePayloadLocalKeyMatch(String payload) async {
    if (!payload.startsWith('${PqcPrivateMessageCodec.prefix}:')) {
      return const DeviceKeyMatch(isKnownFormat: false, hasMatchingKeyset: false);
    }
    final parts = payload.substring(PqcPrivateMessageCodec.prefix.length + 1).split(':');
    if (parts.length != 15) {
      return const DeviceKeyMatch(isKnownFormat: true, hasMatchingKeyset: false);
    }
    final senderDeviceId = parts[0];
    final targetDeviceId = parts[2];
    final keysets = await keyMaterialRegistry.readHistoricalDecryptKeysets();
    final hasMatchingKeyset = keysets.any(
      (item) => item.deviceId == senderDeviceId || item.deviceId == targetDeviceId,
    );
    return DeviceKeyMatch(
      isKnownFormat: true,
      hasMatchingKeyset: hasMatchingKeyset,
      senderDeviceId: senderDeviceId,
      targetDeviceId: targetDeviceId,
    );
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
