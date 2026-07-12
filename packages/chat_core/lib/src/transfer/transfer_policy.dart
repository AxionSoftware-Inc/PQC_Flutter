class TransferPolicy {
  TransferPolicy._();

  static const int maxAttachmentBytes = int.fromEnvironment(
    'MAX_ATTACHMENT_BYTES',
    defaultValue: 2 * 1024 * 1024 * 1024,
  );

  static const int chunkSizeBytes = int.fromEnvironment(
    'ATTACHMENT_CHUNK_BYTES',
    defaultValue: 1024 * 1024,
  );

  static const int maxChunkSizeBytes = int.fromEnvironment(
    'MAX_ATTACHMENT_CHUNK_BYTES',
    defaultValue: 4 * 1024 * 1024,
  );

  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
