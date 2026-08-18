enum AttachmentTransferDirection { upload, download }

enum AttachmentTransferStatus {
  queued,
  encrypting,
  uploading,
  downloading,
  paused,
  retrying,
  verifying,
  completed,
  failed,
}

class AttachmentTransferProgress {
  const AttachmentTransferProgress({
    this.completedChunks = 0,
    this.totalChunks = 0,
  });

  final int completedChunks;
  final int totalChunks;

  double get fraction => totalChunks <= 0
      ? 0
      : (completedChunks / totalChunks).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {
    'completed_chunks': completedChunks,
    'total_chunks': totalChunks,
  };

  factory AttachmentTransferProgress.fromJson(Map<String, dynamic> json) {
    return AttachmentTransferProgress(
      completedChunks: ((json['completed_chunks'] as int? ?? 0).clamp(
        0,
        1 << 31,
      )).toInt(),
      totalChunks: ((json['total_chunks'] as int? ?? 0).clamp(
        0,
        1 << 31,
      )).toInt(),
    );
  }
}

class AttachmentTransferState {
  const AttachmentTransferState({
    required this.localId,
    required this.conversationId,
    required this.direction,
    required this.status,
    required this.filename,
    this.progress = const AttachmentTransferProgress(),
    this.attachmentId,
    this.error,
    this.localPath,
  });

  final String localId;
  final int conversationId;
  final AttachmentTransferDirection direction;
  final AttachmentTransferStatus status;
  final String filename;
  final AttachmentTransferProgress progress;
  final int? attachmentId;
  final String? error;
  final String? localPath;

  Map<String, dynamic> toJson() => {
    'local_id': localId,
    'conversation_id': conversationId,
    'direction': direction.name,
    'status': status.name,
    'filename': filename,
    'progress': progress.toJson(),
    'attachment_id': attachmentId,
    'error': error,
    'local_path': localPath,
  };

  factory AttachmentTransferState.fromJson(Map<String, dynamic> json) {
    final rawProgress = json['progress'];
    return AttachmentTransferState(
      localId: json['local_id'] as String? ?? '',
      conversationId: json['conversation_id'] as int? ?? 0,
      direction: AttachmentTransferDirection.values.firstWhere(
        (item) => item.name == json['direction'],
        orElse: () => AttachmentTransferDirection.download,
      ),
      status: AttachmentTransferStatus.values.firstWhere(
        (item) => item.name == json['status'],
        orElse: () => AttachmentTransferStatus.failed,
      ),
      filename: json['filename'] as String? ?? '',
      progress: rawProgress is Map
          ? AttachmentTransferProgress.fromJson(
              Map<String, dynamic>.from(rawProgress),
            )
          : const AttachmentTransferProgress(),
      attachmentId: json['attachment_id'] as int?,
      error: json['error'] as String?,
      localPath: json['local_path'] as String?,
    );
  }
}

/// Persistence boundary for transfer state. It deliberately stores no file
/// keys, plaintext or ciphertext; the encrypted upload pipeline owns those.
class AttachmentTransferPausedException implements Exception {
  const AttachmentTransferPausedException(this.localId);

  final String localId;

  @override
  String toString() => 'Attachment transfer paused: $localId';
}
