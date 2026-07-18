// Direct whole-file attachment storage. Resumable chunk transfers are not
// part of the normal chat path.
// ignore_for_file: implementation_imports

import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto_core/src/models/attachment.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const _storageKey = 'chat.completed_direct_downloads.v1';

  final ValueNotifier<List<AttachmentTransferState>> transfers = ValueNotifier(
    const [],
  );

  Future<List<AttachmentTransferState>> loadTransfers() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      return transfers.value;
    }
    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      final restored = <AttachmentTransferState>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) {
          continue;
        }
        final path = entry['local_path'] as String?;
        final attachmentId = entry['attachment_id'] as int?;
        if (path == null || attachmentId == null || !File(path).existsSync()) {
          continue;
        }
        restored.add(
          AttachmentTransferState(
            localId: entry['local_id'] as String? ?? 'download-$attachmentId',
            conversationId: entry['conversation_id'] as int? ?? 0,
            direction: AttachmentTransferDirection.download,
            status: AttachmentTransferStatus.completed,
            filename:
                entry['filename'] as String? ?? 'attachment-$attachmentId',
            attachmentId: attachmentId,
            localPath: path,
          ),
        );
      }
      transfers.value = restored;
      await _persistTransfers(restored);
      return restored;
    } catch (_) {
      await preferences.remove(_storageKey);
      transfers.value = const [];
      return const [];
    }
  }

  Future<void> resumePendingDownloads() async {}

  Future<String> saveDirectDownload({
    required ChatAttachment attachment,
    required List<int> bytes,
    required int conversationId,
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
    final transfer = AttachmentTransferState(
      localId: 'download-${attachment.id}',
      conversationId: conversationId,
      direction: AttachmentTransferDirection.download,
      status: AttachmentTransferStatus.completed,
      filename: safeName,
      attachmentId: attachment.id,
      localPath: file.path,
    );
    final updated = [
      ...transfers.value.where((item) => item.attachmentId != attachment.id),
      transfer,
    ];
    transfers.value = updated;
    await _persistTransfers(updated);
    return file.path;
  }

  Future<void> _persistTransfers(List<AttachmentTransferState> value) async {
    final preferences = await SharedPreferences.getInstance();
    final persistent = value
        .where(
          (item) =>
              item.direction == AttachmentTransferDirection.download &&
              item.status == AttachmentTransferStatus.completed &&
              item.attachmentId != null &&
              item.localPath != null,
        )
        .map(
          (item) => <String, dynamic>{
            'local_id': item.localId,
            'conversation_id': item.conversationId,
            'filename': item.filename,
            'attachment_id': item.attachmentId,
            'local_path': item.localPath,
          },
        )
        .toList(growable: false);
    await preferences.setString(_storageKey, jsonEncode(persistent));
  }

  Future<AttachmentTransferState?> resumeTransfer(String localId) async => null;
  Future<void> pauseTransfer(String localId) async {}
  Future<void> cancelTransfer(String localId) async {}
  Future<void> clearCompletedTransfer(String localId) async {}
}
