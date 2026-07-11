import '../../../core/models/conversation.dart';

enum PayloadKind { privateMessage, groupMessage, groupEnvelope }

class PayloadFormatDescriptor {
  const PayloadFormatDescriptor({
    required this.formatId,
    required this.payloadKind,
    required this.prefix,
    required this.introducedAtVersion,
    this.decryptSupported = true,
    this.writeEnabled = false,
  });

  final String formatId;
  final PayloadKind payloadKind;
  final String prefix;
  final String introducedAtVersion;
  final bool decryptSupported;
  final bool writeEnabled;
}

class KeysetSnapshot {
  const KeysetSnapshot({
    required this.keysetId,
    required this.deviceId,
    required this.identityAlgorithm,
    required this.identityPublicKey,
    required this.identityPrivateKey,
    required this.pqcAlgorithm,
    required this.pqcPublicKey,
    required this.pqcSecretKey,
    required this.pqcSigningAlgorithm,
    required this.pqcSigningPublicKey,
    required this.pqcSigningSecretKey,
    required this.status,
    required this.createdAt,
    this.restoredAt,
  });

  final String keysetId;
  final String deviceId;
  final String identityAlgorithm;
  final String identityPublicKey;
  final String identityPrivateKey;
  final String pqcAlgorithm;
  final String pqcPublicKey;
  final String pqcSecretKey;
  final String pqcSigningAlgorithm;
  final String pqcSigningPublicKey;
  final String pqcSigningSecretKey;
  final String status;
  final DateTime createdAt;
  final DateTime? restoredAt;

  bool get isHistoricalReadEnabled =>
      status == 'active' || status == 'historical' || status == 'restored';

  Map<String, dynamic> toJson() {
    return {
      'keyset_id': keysetId,
      'device_id': deviceId,
      'identity_algorithm': identityAlgorithm,
      'identity_public_key': identityPublicKey,
      'identity_private_key': identityPrivateKey,
      'pqc_algorithm': pqcAlgorithm,
      'pqc_public_key': pqcPublicKey,
      'pqc_secret_key': pqcSecretKey,
      'pqc_signing_algorithm': pqcSigningAlgorithm,
      'pqc_signing_public_key': pqcSigningPublicKey,
      'pqc_signing_secret_key': pqcSigningSecretKey,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'restored_at': restoredAt?.toIso8601String(),
    };
  }

  factory KeysetSnapshot.fromJson(Map<String, dynamic> json) {
    return KeysetSnapshot(
      keysetId: json['keyset_id'] as String,
      deviceId: json['device_id'] as String,
      identityAlgorithm: json['identity_algorithm'] as String? ?? '',
      identityPublicKey: json['identity_public_key'] as String? ?? '',
      identityPrivateKey: json['identity_private_key'] as String? ?? '',
      pqcAlgorithm: json['pqc_algorithm'] as String? ?? '',
      pqcPublicKey: json['pqc_public_key'] as String? ?? '',
      pqcSecretKey: json['pqc_secret_key'] as String? ?? '',
      pqcSigningAlgorithm: json['pqc_signing_algorithm'] as String? ?? '',
      pqcSigningPublicKey: json['pqc_signing_public_key'] as String? ?? '',
      pqcSigningSecretKey: json['pqc_signing_secret_key'] as String? ?? '',
      status: json['status'] as String? ?? 'historical',
      createdAt: DateTime.parse(json['created_at'] as String),
      restoredAt: json['restored_at'] == null
          ? null
          : DateTime.tryParse(json['restored_at'] as String),
    );
  }

  KeysetSnapshot copyWith({
    String? status,
    DateTime? restoredAt,
  }) {
    return KeysetSnapshot(
      keysetId: keysetId,
      deviceId: deviceId,
      identityAlgorithm: identityAlgorithm,
      identityPublicKey: identityPublicKey,
      identityPrivateKey: identityPrivateKey,
      pqcAlgorithm: pqcAlgorithm,
      pqcPublicKey: pqcPublicKey,
      pqcSecretKey: pqcSecretKey,
      pqcSigningAlgorithm: pqcSigningAlgorithm,
      pqcSigningPublicKey: pqcSigningPublicKey,
      pqcSigningSecretKey: pqcSigningSecretKey,
      status: status ?? this.status,
      createdAt: createdAt,
      restoredAt: restoredAt ?? this.restoredAt,
    );
  }
}

class HistoricalKeyReference {
  const HistoricalKeyReference({
    required this.deviceId,
    required this.keysetId,
  });

  final String deviceId;
  final String keysetId;
}

class EncryptionRequest {
  const EncryptionRequest({
    required this.currentUserId,
    required this.conversation,
    required this.plaintext,
    required this.usersById,
  });

  final int currentUserId;
  final Conversation conversation;
  final String plaintext;
  final Map<int, dynamic> usersById;
}

class DecryptionRequest {
  const DecryptionRequest({
    required this.currentUserId,
    required this.conversation,
    required this.payload,
    required this.usersById,
  });

  final int currentUserId;
  final Conversation conversation;
  final String payload;
  final Map<int, dynamic> usersById;
}

abstract class DecryptionOutcome {
  const DecryptionOutcome();
}

class DecryptSuccess extends DecryptionOutcome {
  const DecryptSuccess({
    required this.plaintext,
    required this.format,
    this.keyReference,
  });

  final String plaintext;
  final PayloadFormatDescriptor format;
  final HistoricalKeyReference? keyReference;
}

class DecryptNeedsBackupRestore extends DecryptionOutcome {
  const DecryptNeedsBackupRestore({required this.format});

  final PayloadFormatDescriptor format;
}

class DecryptKeyMissing extends DecryptionOutcome {
  const DecryptKeyMissing({required this.format});

  final PayloadFormatDescriptor format;
}

class DecryptFormatUnsupported extends DecryptionOutcome {
  const DecryptFormatUnsupported({required this.payload});

  final String payload;
}

class DecryptCorruptedPayload extends DecryptionOutcome {
  const DecryptCorruptedPayload({required this.format});

  final PayloadFormatDescriptor format;
}

class HistoricalDecryptCheck {
  const HistoricalDecryptCheck({
    required this.hasHistoricalCapability,
    required this.availableKeysets,
  });

  final bool hasHistoricalCapability;
  final int availableKeysets;
}

class BackupExportRequest {
  const BackupExportRequest({required this.recoveryPassphrase});

  final String recoveryPassphrase;
}

class BackupImportRequest {
  const BackupImportRequest({
    required this.recoveryPassphrase,
    required this.encryptedBlob,
  });

  final String recoveryPassphrase;
  final String encryptedBlob;
}
