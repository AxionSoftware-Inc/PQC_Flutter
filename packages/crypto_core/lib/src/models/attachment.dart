class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.storageKey,
    this.thumbnailKey = '',
    this.cipherVersion = 'attachment:v1',
    this.plaintextSize = 0,
    this.ciphertextSize = 0,
    this.chunkSize = 0,
    this.plaintextSha256 = '',
    this.manifestSha256 = '',
    this.fileKeyWrap = '',
    this.createdAt,
  });

  final int id;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String storageKey;
  final String thumbnailKey;
  final String cipherVersion;
  final int plaintextSize;
  final int ciphertextSize;
  final int chunkSize;
  final String plaintextSha256;
  final String manifestSha256;
  final String fileKeyWrap;
  final DateTime? createdAt;

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as int,
      filename: json['filename'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      sizeBytes: json['size_bytes'] as int? ?? 0,
      storageKey: json['storage_key'] as String? ?? '',
      thumbnailKey: json['thumbnail_key'] as String? ?? '',
      cipherVersion: json['cipher_version'] as String? ?? 'attachment:v1',
      plaintextSize: json['plaintext_size'] as int? ?? 0,
      ciphertextSize: json['ciphertext_size'] as int? ?? 0,
      chunkSize: json['chunk_size'] as int? ?? 0,
      plaintextSha256: json['plaintext_sha256'] as String? ?? '',
      manifestSha256: json['manifest_sha256'] as String? ?? '',
      fileKeyWrap: json['file_key_wrap'] as String? ?? '',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
