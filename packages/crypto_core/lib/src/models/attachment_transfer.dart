class AttachmentEncryptionDescriptor {
  const AttachmentEncryptionDescriptor({
    required this.cipherVersion,
    required this.fileKeyBase64,
    required this.nonceSeedBase64,
    this.conversationEpochId = '',
    this.manifestSequence = 0,
  });

  final String cipherVersion;
  final String fileKeyBase64;
  final String nonceSeedBase64;
  final String conversationEpochId;
  final int manifestSequence;

  Map<String, dynamic> toJson() {
    return {
      'cipher_version': cipherVersion,
      'file_key_base64': fileKeyBase64,
      'nonce_seed_base64': nonceSeedBase64,
      'conversation_epoch_id': conversationEpochId,
      'manifest_sequence': manifestSequence,
    };
  }

  factory AttachmentEncryptionDescriptor.fromJson(Map<String, dynamic> json) {
    return AttachmentEncryptionDescriptor(
      cipherVersion: json['cipher_version'] as String? ?? 'attachment:v1',
      fileKeyBase64: json['file_key_base64'] as String? ?? '',
      nonceSeedBase64: json['nonce_seed_base64'] as String? ?? '',
      conversationEpochId: json['conversation_epoch_id'] as String? ?? '',
      manifestSequence: json['manifest_sequence'] as int? ?? 0,
    );
  }
}

class EncryptedAttachmentManifest {
  const EncryptedAttachmentManifest({
    required this.filename,
    required this.mimeType,
    required this.cipherVersion,
    required this.chunkSize,
    required this.plaintextSize,
    required this.ciphertextSize,
    required this.totalChunks,
    required this.plaintextSha256,
    required this.manifestSha256,
    required this.fileKeyWrap,
    this.conversationEpochId = '',
    this.recoveryManifestSequence = 0,
  });

  final String filename;
  final String mimeType;
  final String cipherVersion;
  final int chunkSize;
  final int plaintextSize;
  final int ciphertextSize;
  final int totalChunks;
  final String plaintextSha256;
  final String manifestSha256;
  final String fileKeyWrap;
  final String conversationEpochId;
  final int recoveryManifestSequence;

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'mime_type': mimeType,
      'cipher_version': cipherVersion,
      'chunk_size': chunkSize,
      'plaintext_size': plaintextSize,
      'ciphertext_size': ciphertextSize,
      'total_chunks': totalChunks,
      'plaintext_sha256': plaintextSha256,
      'manifest_sha256': manifestSha256,
      'file_key_wrap': fileKeyWrap,
      'conversation_epoch_id': conversationEpochId,
      'recovery_manifest_sequence': recoveryManifestSequence,
    };
  }
}

class AttachmentKeyEnvelope {
  const AttachmentKeyEnvelope({
    required this.fileKeyBase64,
    required this.nonceSeedBase64,
    required this.cipherVersion,
    this.conversationEpochId = '',
    this.recoveryManifestSequence = 0,
  });

  final String fileKeyBase64;
  final String nonceSeedBase64;
  final String cipherVersion;
  final String conversationEpochId;
  final int recoveryManifestSequence;

  Map<String, dynamic> toJson() {
    return {
      'file_key_base64': fileKeyBase64,
      'nonce_seed_base64': nonceSeedBase64,
      'cipher_version': cipherVersion,
      'conversation_epoch_id': conversationEpochId,
      'recovery_manifest_sequence': recoveryManifestSequence,
    };
  }

  factory AttachmentKeyEnvelope.fromJson(Map<String, dynamic> json) {
    return AttachmentKeyEnvelope(
      fileKeyBase64: json['file_key_base64'] as String? ?? '',
      nonceSeedBase64: json['nonce_seed_base64'] as String? ?? '',
      cipherVersion: json['cipher_version'] as String? ?? 'attachment:v1',
      conversationEpochId: json['conversation_epoch_id'] as String? ?? '',
      recoveryManifestSequence: json['recovery_manifest_sequence'] as int? ?? 0,
    );
  }
}
