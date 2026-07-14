// Direct whole-file attachment storage. Resumable chunk transfers are not
// part of the normal chat path.
// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto_core/src/models/attachment.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../chat/data/chat_remote_data_source.dart';

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
    this.completedChunks = 1,
    this.totalChunks = 1,
  });

  final int completedChunks;
  final int totalChunks;

  double get fraction => totalChunks <= 0 ? 0 : completedChunks / totalChunks;
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
}

class AttachmentTransferFacade {
  AttachmentTransferFacade({required ChatRemoteDataSource remoteDataSource});

  final ValueNotifier<List<AttachmentTransferState>> transfers = ValueNotifier(
    const [],
  );

  Future<List<AttachmentTransferState>> loadTransfers() async => const [];

  Future<void> resumePendingDownloads() async {}

  Future<String> saveDirectDownload({
    required ChatAttachment attachment,
    required List<int> bytes,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final safeName = attachment.filename.trim().isEmpty
        ? 'attachment-${attachment.id}'
        : p.basename(attachment.filename);
    final file = File(
      p.join(directory.path, 'attachments', '${attachment.id}-$safeName'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<AttachmentTransferState?> resumeTransfer(String localId) async => null;
  Future<void> pauseTransfer(String localId) async {}
  Future<void> cancelTransfer(String localId) async {}
  Future<void> clearCompletedTransfer(String localId) async {}
}
