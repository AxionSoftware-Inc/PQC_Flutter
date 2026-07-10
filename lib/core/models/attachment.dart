class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.storageKey,
    this.thumbnailKey = '',
    this.createdAt,
  });

  final int id;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String storageKey;
  final String thumbnailKey;
  final DateTime? createdAt;

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as int,
      filename: json['filename'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      sizeBytes: json['size_bytes'] as int? ?? 0,
      storageKey: json['storage_key'] as String? ?? '',
      thumbnailKey: json['thumbnail_key'] as String? ?? '',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
