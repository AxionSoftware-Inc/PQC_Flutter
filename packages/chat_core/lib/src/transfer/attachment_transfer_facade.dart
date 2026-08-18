import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto_core/crypto_core.dart' show ChatAttachment;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../chat/data/chat_remote_data_source.dart';
import 'attachment_transfer_models.dart';
import 'attachment_transfer_store.dart';

class AttachmentTransferFacade {
  AttachmentTransferFacade({
    required this._remoteDataSource,
    AttachmentTransferStore? store,
  }) : _store = store ?? SharedPreferencesAttachmentTransferStore();

  // Kept as an explicit dependency because transfer orchestration owns the
  // remote session boundary, even though persistence methods are local.
  final ChatRemoteDataSource _remoteDataSource;
  final AttachmentTransferStore _store;

  ChatRemoteDataSource get remoteDataSource => _remoteDataSource;

  final ValueNotifier<List<AttachmentTransferState>> transfers = ValueNotifier(
    const [],
  );
  bool _loaded = false;
  Future<void>? _writeInFlight;

  Future<List<AttachmentTransferState>> loadTransfers() async {
    if (!_loaded) {
      transfers.value = List.unmodifiable(await _store.readAll());
      _loaded = true;
    }
    return transfers.value;
  }

  Future<void> resumePendingDownloads() async {
    await loadTransfers();
    // A download is resumed explicitly by the screen after it has the
    // conversation key. Here we recover only the visible state.
    for (final transfer in transfers.value) {
      if (transfer.direction == AttachmentTransferDirection.download &&
          transfer.status == AttachmentTransferStatus.downloading) {
        await _replace(
          transfer.copyWith(status: AttachmentTransferStatus.paused),
        );
      }
    }
  }

  Future<void> beginUpload({
    required String localId,
    required int conversationId,
    required String filename,
    required int totalChunks,
  }) async {
    await _replace(
      AttachmentTransferState(
        localId: localId,
        conversationId: conversationId,
        direction: AttachmentTransferDirection.upload,
        status: AttachmentTransferStatus.queued,
        filename: filename,
        progress: AttachmentTransferProgress(totalChunks: totalChunks),
      ),
    );
  }

  Future<void> updateUploadProgress({
    required String localId,
    required int completedChunks,
    required int totalChunks,
    int? attachmentId,
  }) async {
    final current = _find(localId);
    if (current == null) return;
    await _replace(
      current.copyWith(
        status: AttachmentTransferStatus.uploading,
        attachmentId: attachmentId ?? current.attachmentId,
        progress: AttachmentTransferProgress(
          completedChunks: completedChunks,
          totalChunks: totalChunks,
        ),
      ),
    );
  }

  Future<void> beginDownload({
    required String localId,
    required int conversationId,
    required String filename,
    required int totalChunks,
    required int attachmentId,
  }) async {
    await _replace(
      AttachmentTransferState(
        localId: localId,
        conversationId: conversationId,
        direction: AttachmentTransferDirection.download,
        status: AttachmentTransferStatus.downloading,
        filename: filename,
        progress: AttachmentTransferProgress(totalChunks: totalChunks),
        attachmentId: attachmentId,
      ),
    );
  }

  Future<void> updateDownloadProgress({
    required String localId,
    required int completedChunks,
    required int totalChunks,
  }) async {
    final current = _find(localId);
    if (current == null) return;
    await _replace(
      current.copyWith(
        status: AttachmentTransferStatus.downloading,
        progress: AttachmentTransferProgress(
          completedChunks: completedChunks,
          totalChunks: totalChunks,
        ),
      ),
    );
  }

  Future<void> completeUpload(String localId, {int? attachmentId}) async {
    final current = _find(localId);
    if (current == null) return;
    await _replace(
      current.copyWith(
        status: AttachmentTransferStatus.completed,
        attachmentId: attachmentId ?? current.attachmentId,
        progress: AttachmentTransferProgress(
          completedChunks: current.progress.totalChunks,
          totalChunks: current.progress.totalChunks,
        ),
        error: null,
      ),
    );
  }

  Future<void> failTransfer(String localId, Object error) async {
    final current = _find(localId);
    if (current == null) return;
    await _replace(
      current.copyWith(
        status: AttachmentTransferStatus.failed,
        error: error.toString(),
      ),
    );
  }

  Future<void> throwIfPaused(String localId) async {
    final current = _find(localId);
    if (current?.status == AttachmentTransferStatus.paused) {
      throw AttachmentTransferPausedException(localId);
    }
  }

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
    final existing = _find('download:${attachment.id}');
    await _replace(
      AttachmentTransferState(
        localId: 'download:${attachment.id}',
        conversationId: existing?.conversationId ?? 0,
        direction: AttachmentTransferDirection.download,
        status: AttachmentTransferStatus.completed,
        filename: safeName,
        progress: const AttachmentTransferProgress(
          completedChunks: 1,
          totalChunks: 1,
        ),
        attachmentId: attachment.id,
        localPath: file.path,
      ),
    );
    return file.path;
  }

  Future<AttachmentTransferState?> resumeTransfer(String localId) async {
    final current = _find(localId);
    if (current == null) return null;
    final resumed = current.copyWith(
      status: AttachmentTransferStatus.queued,
      error: null,
    );
    await _replace(resumed);
    return resumed;
  }

  Future<void> pauseTransfer(String localId) async {
    final current = _find(localId);
    if (current == null ||
        current.status == AttachmentTransferStatus.completed) {
      return;
    }
    await _replace(current.copyWith(status: AttachmentTransferStatus.paused));
  }

  Future<void> cancelTransfer(String localId) async {
    await loadTransfers();
    final next = transfers.value.where((item) => item.localId != localId);
    await _commit(next);
  }

  Future<void> clearCompletedTransfer(String localId) async {
    final current = _find(localId);
    if (current?.status != AttachmentTransferStatus.completed) return;
    await cancelTransfer(localId);
  }

  AttachmentTransferState? _find(String localId) {
    for (final transfer in transfers.value) {
      if (transfer.localId == localId) return transfer;
    }
    return null;
  }

  Future<void> _replace(AttachmentTransferState value) async {
    await loadTransfers();
    final next = [
      for (final item in transfers.value)
        if (item.localId != value.localId) item,
      value,
    ];
    await _commit(next);
  }

  Future<void> _commit(Iterable<AttachmentTransferState> values) async {
    final next = List<AttachmentTransferState>.unmodifiable(values);
    transfers.value = next;
    final previous = _writeInFlight;
    if (previous != null) await previous;
    final operation = _store.writeAll(next);
    _writeInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_writeInFlight, operation)) _writeInFlight = null;
    }
  }
}

extension on AttachmentTransferState {
  AttachmentTransferState copyWith({
    AttachmentTransferStatus? status,
    AttachmentTransferProgress? progress,
    int? attachmentId,
    String? error,
    String? localPath,
  }) {
    return AttachmentTransferState(
      localId: localId,
      conversationId: conversationId,
      direction: direction,
      status: status ?? this.status,
      filename: filename,
      progress: progress ?? this.progress,
      attachmentId: attachmentId ?? this.attachmentId,
      error: error,
      localPath: localPath ?? this.localPath,
    );
  }
}
