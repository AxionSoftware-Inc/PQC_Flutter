// ignore_for_file: implementation_imports, prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:crypto_core/src/core/storage/local_data_protector.dart';
import 'package:crypto_core/src/crypto/attachment_crypto_service.dart';
import 'package:crypto_core/src/models/attachment.dart';
import 'package:crypto_core/src/models/attachment_transfer.dart';
import 'package:crypto_core/src/models/conversation.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/network/api_client.dart';
import '../chat/application/chat_models.dart';
import '../chat/data/chat_remote_data_source.dart';
import 'transfer_policy.dart';

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
    required this.completedChunks,
    required this.totalChunks,
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
    required this.progress,
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

class _StoredTransferSession {
  const _StoredTransferSession({
    required this.localId,
    required this.direction,
    required this.conversationId,
    required this.filename,
    required this.mimeType,
    required this.localSourcePath,
    required this.remoteSessionId,
    required this.chunkSize,
    required this.totalChunks,
    required this.plaintextSize,
    required this.ciphertextSize,
    required this.plaintextSha256,
    required this.manifestSha256,
    required this.fileKeyWrap,
    required this.encryptedDescriptor,
    required this.completedChunks,
    required this.status,
    this.attachmentId,
    this.lastError,
    this.downloadTargetPath,
  });

  final String localId;
  final String direction;
  final int conversationId;
  final String filename;
  final String mimeType;
  final String localSourcePath;
  final String remoteSessionId;
  final int chunkSize;
  final int totalChunks;
  final int plaintextSize;
  final int ciphertextSize;
  final String plaintextSha256;
  final String manifestSha256;
  final String fileKeyWrap;
  final String encryptedDescriptor;
  final List<int> completedChunks;
  final String status;
  final int? attachmentId;
  final String? lastError;
  final String? downloadTargetPath;

  Map<String, dynamic> toJson() {
    return {
      'local_id': localId,
      'direction': direction,
      'conversation_id': conversationId,
      'filename': filename,
      'mime_type': mimeType,
      'local_source_path': localSourcePath,
      'remote_session_id': remoteSessionId,
      'chunk_size': chunkSize,
      'total_chunks': totalChunks,
      'plaintext_size': plaintextSize,
      'ciphertext_size': ciphertextSize,
      'plaintext_sha256': plaintextSha256,
      'manifest_sha256': manifestSha256,
      'file_key_wrap': fileKeyWrap,
      'encrypted_descriptor': encryptedDescriptor,
      'completed_chunks': completedChunks,
      'status': status,
      'attachment_id': attachmentId,
      'last_error': lastError,
      'download_target_path': downloadTargetPath,
    };
  }

  factory _StoredTransferSession.fromJson(Map<String, dynamic> json) {
    return _StoredTransferSession(
      localId: json['local_id'] as String? ?? '',
      direction: json['direction'] as String? ?? 'upload',
      conversationId: json['conversation_id'] as int? ?? 0,
      filename: json['filename'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      localSourcePath: json['local_source_path'] as String? ?? '',
      remoteSessionId: json['remote_session_id'] as String? ?? '',
      chunkSize: json['chunk_size'] as int? ?? 0,
      totalChunks: json['total_chunks'] as int? ?? 0,
      plaintextSize: json['plaintext_size'] as int? ?? 0,
      ciphertextSize: json['ciphertext_size'] as int? ?? 0,
      plaintextSha256: json['plaintext_sha256'] as String? ?? '',
      manifestSha256: json['manifest_sha256'] as String? ?? '',
      fileKeyWrap: json['file_key_wrap'] as String? ?? '',
      encryptedDescriptor: json['encrypted_descriptor'] as String? ?? '',
      completedChunks: (json['completed_chunks'] as List<dynamic>? ?? const [])
          .whereType<int>()
          .toList(),
      status: json['status'] as String? ?? AttachmentTransferStatus.queued.name,
      attachmentId: json['attachment_id'] as int?,
      lastError: json['last_error'] as String?,
      downloadTargetPath: json['download_target_path'] as String?,
    );
  }

  _StoredTransferSession copyWith({
    List<int>? completedChunks,
    String? status,
    int? attachmentId,
    String? lastError,
    String? remoteSessionId,
    String? encryptedDescriptor,
    String? downloadTargetPath,
  }) {
    return _StoredTransferSession(
      localId: localId,
      direction: direction,
      conversationId: conversationId,
      filename: filename,
      mimeType: mimeType,
      localSourcePath: localSourcePath,
      remoteSessionId: remoteSessionId ?? this.remoteSessionId,
      chunkSize: chunkSize,
      totalChunks: totalChunks,
      plaintextSize: plaintextSize,
      ciphertextSize: ciphertextSize,
      plaintextSha256: plaintextSha256,
      manifestSha256: manifestSha256,
      fileKeyWrap: fileKeyWrap,
      encryptedDescriptor: encryptedDescriptor ?? this.encryptedDescriptor,
      completedChunks: completedChunks ?? this.completedChunks,
      status: status ?? this.status,
      attachmentId: attachmentId ?? this.attachmentId,
      lastError: lastError ?? this.lastError,
      downloadTargetPath: downloadTargetPath ?? this.downloadTargetPath,
    );
  }
}

class TransferSessionStore {
  TransferSessionStore();

  File? _cacheFile;

  Future<File> _file() async {
    final existing = _cacheFile;
    if (existing != null) {
      return existing;
    }
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'attachment_transfer_sessions.json'));
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString('[]');
    }
    _cacheFile = file;
    return file;
  }

  Future<List<_StoredTransferSession>> _readAll() async {
    final file = await _file();
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => _StoredTransferSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<_StoredTransferSession?> _readByLocalId(String localId) async {
    final sessions = await _readAll();
    for (final session in sessions) {
      if (session.localId == localId) {
        return session;
      }
    }
    return null;
  }

  Future<void> _upsert(_StoredTransferSession session) async {
    final sessions = await _readAll();
    final index = sessions.indexWhere((item) => item.localId == session.localId);
    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.add(session);
    }
    await _writeAll(sessions);
  }

  Future<void> _remove(String localId) async {
    final sessions = await _readAll();
    sessions.removeWhere((item) => item.localId == localId);
    await _writeAll(sessions);
  }

  Future<void> _writeAll(List<_StoredTransferSession> sessions) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(sessions.map((item) => item.toJson()).toList()),
    );
  }
}

class AttachmentTransferFacade {
  AttachmentTransferFacade({
    required ChatRemoteDataSource remoteDataSource,
    required LocalDataProtector localDataProtector,
    AttachmentCryptoService? attachmentCryptoService,
    TransferSessionStore? sessionStore,
    int chunkSizeBytes = TransferPolicy.chunkSizeBytes,
    int maxAttachmentBytes = TransferPolicy.maxAttachmentBytes,
  }) : _remoteDataSource = remoteDataSource,
       _localDataProtector = localDataProtector,
       _attachmentCryptoService =
           attachmentCryptoService ?? AttachmentCryptoService(),
       _sessionStore = sessionStore ?? TransferSessionStore(),
       _chunkSizeBytes = chunkSizeBytes,
       _maxAttachmentBytes = maxAttachmentBytes;

  final ChatRemoteDataSource _remoteDataSource;
  final LocalDataProtector _localDataProtector;
  final AttachmentCryptoService _attachmentCryptoService;
  final TransferSessionStore _sessionStore;
  final int _chunkSizeBytes;
  final int _maxAttachmentBytes;
  final ValueNotifier<List<AttachmentTransferState>> transfers =
      ValueNotifier(const []);

  Future<ChatAttachment> uploadAttachment({
    required Conversation conversation,
    required PendingAttachmentUpload attachment,
    required Future<String> Function(String plaintext) encryptKeyEnvelope,
  }) async {
    final sourceFile = await _resolveSourceFile(attachment);
    await _validateUploadSize(
      attachment: attachment,
      sourceFile: sourceFile,
    );
    final localId = await _buildLocalId(
      conversationId: conversation.id,
      file: sourceFile,
      filename: attachment.filename,
    );
    final existing = await _sessionStore._readByLocalId(localId);
    final session = existing ??
        await _createUploadSession(
          localId: localId,
          conversation: conversation,
          attachment: attachment,
          sourceFile: sourceFile,
          encryptKeyEnvelope: encryptKeyEnvelope,
        );
    try {
      await _emitSession(
        session.copyWith(status: AttachmentTransferStatus.uploading.name),
      );
      final completed = await _continueUploadSession(
        session: session.copyWith(
          status: AttachmentTransferStatus.uploading.name,
        ),
        sourceFile: sourceFile,
      );
      await _sessionStore._remove(session.localId);
      await _refreshTransfers();
      return completed;
    } on ApiException catch (error) {
      await _sessionStore._upsert(
        session.copyWith(
          completedChunks: session.completedChunks,
          status: AttachmentTransferStatus.failed.name,
          lastError: error.message,
        ),
      );
      await _refreshTransfers();
      rethrow;
    }
  }

  Future<String> downloadAttachment({
    required Conversation conversation,
    required ChatAttachment attachment,
    required Future<String> Function(String payload) decryptKeyEnvelope,
  }) async {
    final localId = 'download-${attachment.id}';
    final descriptorAttachment = await _remoteDataSource
        .fetchAttachmentDownloadDescriptor(attachment.id);
    final existing = await _sessionStore._readByLocalId(localId);
    final targetFile = await _resolveDownloadFile(descriptorAttachment);
    final session =
        existing ??
        _StoredTransferSession(
          localId: localId,
          direction: AttachmentTransferDirection.download.name,
          conversationId: conversation.id,
          filename: descriptorAttachment.filename,
          mimeType: descriptorAttachment.mimeType,
          localSourcePath: targetFile.path,
          remoteSessionId: '',
          chunkSize: descriptorAttachment.chunkSize,
          totalChunks: _calculateTotalChunks(
            descriptorAttachment.plaintextSize,
            descriptorAttachment.chunkSize,
          ),
          plaintextSize: descriptorAttachment.plaintextSize,
          ciphertextSize: descriptorAttachment.ciphertextSize,
          plaintextSha256: descriptorAttachment.plaintextSha256,
          manifestSha256: descriptorAttachment.manifestSha256,
          fileKeyWrap: descriptorAttachment.fileKeyWrap,
          encryptedDescriptor: '',
          completedChunks: const [],
          status: AttachmentTransferStatus.queued.name,
          attachmentId: descriptorAttachment.id,
          downloadTargetPath: targetFile.path,
        );
    final descriptor = session.encryptedDescriptor.isNotEmpty
        ? await _readDescriptor(session.encryptedDescriptor)
        : await _resolveDownloadDescriptor(
            fileKeyWrap: descriptorAttachment.fileKeyWrap,
            decryptKeyEnvelope: decryptKeyEnvelope,
          );
    final protectedDescriptor = session.encryptedDescriptor.isNotEmpty
        ? session.encryptedDescriptor
        : await _localDataProtector.protect(jsonEncode(descriptor.toJson()));
    final storedSession = session.copyWith(
      encryptedDescriptor: protectedDescriptor,
      status: AttachmentTransferStatus.downloading.name,
      downloadTargetPath: targetFile.path,
    );
    final completedChunks = storedSession.completedChunks.toSet();
    await _emitSession(storedSession);
    try {
      final completedPath = await _continueDownloadSession(
        session: storedSession,
        descriptor: descriptor,
        attachmentId: descriptorAttachment.id,
        targetFile: targetFile,
      );
      return completedPath;
    } on ApiException catch (error) {
      await _sessionStore._upsert(
        storedSession.copyWith(
          completedChunks: completedChunks.toList()..sort(),
          status: AttachmentTransferStatus.failed.name,
          lastError: error.message,
          downloadTargetPath: targetFile.path,
        ),
      );
      await _refreshTransfers();
      rethrow;
    }
  }

  Future<List<AttachmentTransferState>> loadTransfers() async {
    await _refreshTransfers();
    return transfers.value;
  }

  Future<void> pauseTransfer(String localId) async {
    final existing = await _sessionStore._readByLocalId(localId);
    if (existing == null) {
      return;
    }
    await _sessionStore._upsert(
      existing.copyWith(status: AttachmentTransferStatus.paused.name),
    );
    await _refreshTransfers();
  }

  Future<AttachmentTransferState?> resumeTransfer(String localId) async {
    final existing = await _sessionStore._readByLocalId(localId);
    if (existing == null) {
      return null;
    }
    final resumed = existing.copyWith(
      status: existing.direction == AttachmentTransferDirection.download.name
          ? AttachmentTransferStatus.downloading.name
          : AttachmentTransferStatus.uploading.name,
      lastError: null,
    );
    await _sessionStore._upsert(resumed);
    await _refreshTransfers();
    return transfers.value.cast<AttachmentTransferState?>().firstWhere(
          (item) => item?.localId == localId,
          orElse: () => null,
        );
  }

  Future<void> cancelTransfer(String localId) async {
    final existing = await _sessionStore._readByLocalId(localId);
    if (existing == null) {
      return;
    }
    if (existing.direction == AttachmentTransferDirection.download.name) {
      final targetPath = existing.downloadTargetPath ?? existing.localSourcePath;
      final file = File(targetPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _sessionStore._remove(localId);
    await _refreshTransfers();
  }

  Future<void> clearCompletedTransfer(String localId) async {
    await _sessionStore._remove(localId);
    await _refreshTransfers();
  }

  Future<void> resumePendingDownloads() async {
    final sessions = await _sessionStore._readAll();
    for (final session in sessions) {
      if (session.direction != AttachmentTransferDirection.download.name ||
          session.status == AttachmentTransferStatus.completed.name ||
          session.status == AttachmentTransferStatus.paused.name ||
          session.encryptedDescriptor.isEmpty ||
          session.attachmentId == null) {
        continue;
      }
      final targetPath = session.downloadTargetPath ?? session.localSourcePath;
      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);
      if (!await targetFile.exists()) {
        await targetFile.create(recursive: true);
      }
      final descriptor = await _readDescriptor(session.encryptedDescriptor);
      try {
        await _continueDownloadSession(
          session: session.copyWith(
            status: AttachmentTransferStatus.downloading.name,
          ),
          descriptor: descriptor,
          attachmentId: session.attachmentId!,
          targetFile: targetFile,
        );
      } on ApiException {
        // Session state is already persisted by _continueDownloadSession.
      }
    }
    await _refreshTransfers();
  }

  Future<_StoredTransferSession> _createUploadSession({
    required String localId,
    required Conversation conversation,
    required PendingAttachmentUpload attachment,
    required File sourceFile,
    required Future<String> Function(String plaintext) encryptKeyEnvelope,
  }) async {
    final descriptor = _attachmentCryptoService.generateDescriptor();
    final analysis = await _attachmentCryptoService.analyzeFile(
      file: sourceFile,
      chunkSize: _chunkSizeBytes,
    );
    final keyEnvelope = AttachmentKeyEnvelope(
      fileKeyBase64: descriptor.fileKeyBase64,
      nonceSeedBase64: descriptor.nonceSeedBase64,
      cipherVersion: descriptor.cipherVersion,
    );
    final fileKeyWrap = await encryptKeyEnvelope(
      jsonEncode(keyEnvelope.toJson()),
    );
    final preliminaryManifest = EncryptedAttachmentManifest(
      filename: attachment.filename,
      mimeType: attachment.mimeType,
      cipherVersion: descriptor.cipherVersion,
      chunkSize: _chunkSizeBytes,
      plaintextSize: analysis.plaintextSize,
      ciphertextSize: analysis.ciphertextSize,
      totalChunks: analysis.totalChunks,
      plaintextSha256: analysis.plaintextSha256,
      manifestSha256: '',
      fileKeyWrap: fileKeyWrap,
    );
    final manifestSha256 = await _attachmentCryptoService.buildManifestSha256(
      preliminaryManifest,
    );
    final remoteSession = await _remoteDataSource.createAttachmentSession(
      conversation.id,
      filename: attachment.filename,
      mimeType: attachment.mimeType,
      cipherVersion: descriptor.cipherVersion,
      plaintextSize: analysis.plaintextSize,
      ciphertextSize: analysis.ciphertextSize,
      chunkSize: _chunkSizeBytes,
      totalChunks: analysis.totalChunks,
      plaintextSha256: analysis.plaintextSha256,
      manifestSha256: manifestSha256,
      fileKeyWrap: fileKeyWrap,
    );
    final encryptedDescriptor = await _localDataProtector.protect(
      jsonEncode(descriptor.toJson()),
    );
    final stored = _StoredTransferSession(
      localId: localId,
      direction: AttachmentTransferDirection.upload.name,
      conversationId: conversation.id,
      filename: attachment.filename,
      mimeType: attachment.mimeType,
      localSourcePath: sourceFile.path,
      remoteSessionId: remoteSession.sessionId,
      chunkSize: _chunkSizeBytes,
      totalChunks: analysis.totalChunks,
      plaintextSize: analysis.plaintextSize,
      ciphertextSize: analysis.ciphertextSize,
      plaintextSha256: analysis.plaintextSha256,
      manifestSha256: manifestSha256,
      fileKeyWrap: fileKeyWrap,
      encryptedDescriptor: encryptedDescriptor,
      completedChunks: const [],
      status: AttachmentTransferStatus.queued.name,
    );
    await _sessionStore._upsert(stored);
    return stored;
  }

  Future<File> _resolveSourceFile(PendingAttachmentUpload attachment) async {
    if (attachment.filePath != null && attachment.filePath!.trim().isNotEmpty) {
      return File(attachment.filePath!);
    }
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      p.join(directory.path, 'attachment_sources', attachment.filename),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(attachment.bytes ?? const [], flush: true);
    return file;
  }

  Future<void> _validateUploadSize({
    required PendingAttachmentUpload attachment,
    required File sourceFile,
  }) async {
    final configuredSize = attachment.sizeBytes > 0
        ? attachment.sizeBytes
        : (await sourceFile.stat()).size;
    if (configuredSize > _maxAttachmentBytes) {
      throw ApiException(
        'File is too large. Current limit is ${TransferPolicy.formatBytes(_maxAttachmentBytes)}.',
        code: 'attachment_too_large',
      );
    }
  }

  Future<File> _resolveDownloadFile(ChatAttachment attachment) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      p.join(
        directory.path,
        'downloaded_attachments',
        '${attachment.id}_${attachment.filename}',
      ),
    );
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  Future<String> _buildLocalId({
    required int conversationId,
    required File file,
    required String filename,
  }) async {
    final stat = await file.stat();
    final fingerprint = [
      '$conversationId',
      file.path,
      filename,
      '${stat.size}',
      '${stat.modified.millisecondsSinceEpoch}',
    ].join('|');
    return crypto.sha256.convert(utf8.encode(fingerprint)).toString();
  }

  Future<AttachmentEncryptionDescriptor> _readDescriptor(String protected) async {
    final raw = await _localDataProtector.unprotect(protected);
    return AttachmentEncryptionDescriptor.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  int _calculateTotalChunks(int plaintextSize, int chunkSize) {
    if (plaintextSize <= 0 || chunkSize <= 0) {
      return 0;
    }
    return ((plaintextSize + chunkSize - 1) / chunkSize).floor();
  }

  Future<AttachmentEncryptionDescriptor> _resolveDownloadDescriptor({
    required String fileKeyWrap,
    required Future<String> Function(String payload) decryptKeyEnvelope,
  }) async {
    final decryptedEnvelope = await decryptKeyEnvelope(fileKeyWrap);
    final envelope = AttachmentKeyEnvelope.fromJson(
      jsonDecode(decryptedEnvelope) as Map<String, dynamic>,
    );
    return AttachmentEncryptionDescriptor(
      cipherVersion: envelope.cipherVersion,
      fileKeyBase64: envelope.fileKeyBase64,
      nonceSeedBase64: envelope.nonceSeedBase64,
    );
  }

  Future<ChatAttachment> _continueUploadSession({
    required _StoredTransferSession session,
    required File sourceFile,
  }) async {
    final descriptor = await _readDescriptor(session.encryptedDescriptor);
    final remoteSession = await _remoteDataSource.getAttachmentSession(
      session.remoteSessionId,
    );
    final uploadedChunks = {
      ...session.completedChunks,
      ...remoteSession.receivedChunks,
    };
    var current = session.copyWith(
      completedChunks: uploadedChunks.toList()..sort(),
      status: AttachmentTransferStatus.uploading.name,
      lastError: null,
    );
    await _emitSession(current);
    for (var chunkIndex = 0; chunkIndex < current.totalChunks; chunkIndex++) {
      current = await _guardTransferLoop(current.localId);
      if (uploadedChunks.contains(chunkIndex)) {
        continue;
      }
      final encryptedChunk = await _attachmentCryptoService.encryptChunk(
        file: sourceFile,
        descriptor: descriptor,
        chunkSize: current.chunkSize,
        chunkIndex: chunkIndex,
      );
      final checksum = crypto.sha256.convert(encryptedChunk.ciphertext).toString();
      await _remoteDataSource.uploadAttachmentChunk(
        current.remoteSessionId,
        chunkIndex: chunkIndex,
        bytes: encryptedChunk.ciphertext,
        ciphertextSha256: checksum,
      );
      uploadedChunks.add(chunkIndex);
      current = current.copyWith(
        completedChunks: uploadedChunks.toList()..sort(),
        status: AttachmentTransferStatus.uploading.name,
        lastError: null,
      );
      await _emitSession(current);
    }
    final completed = await _remoteDataSource.completeAttachmentSession(
      current.remoteSessionId,
      manifestSha256: current.manifestSha256,
    );
    return completed;
  }

  Future<String> _continueDownloadSession({
    required _StoredTransferSession session,
    required AttachmentEncryptionDescriptor descriptor,
    required int attachmentId,
    required File targetFile,
  }) async {
    final completedChunks = session.completedChunks.toSet();
    var current = session.copyWith(
      status: AttachmentTransferStatus.downloading.name,
      lastError: null,
      downloadTargetPath: targetFile.path,
    );
    if (completedChunks.isEmpty) {
      await targetFile.writeAsBytes(const [], flush: true);
    } else if (!await targetFile.exists()) {
      await targetFile.create(recursive: true);
    }
    final writer = await targetFile.open(mode: FileMode.writeOnlyAppend);
    try {
      for (var chunkIndex = 0; chunkIndex < current.totalChunks; chunkIndex++) {
        current = await _guardTransferLoop(current.localId);
        if (completedChunks.contains(chunkIndex)) {
          continue;
        }
        final ciphertext = await _remoteDataSource.downloadAttachmentChunk(
          attachmentId,
          chunkIndex: chunkIndex,
        );
        final plaintext = await _attachmentCryptoService.decryptChunk(
          ciphertext: ciphertext,
          descriptor: descriptor,
          chunkIndex: chunkIndex,
        );
        await writer.setPosition(chunkIndex * current.chunkSize);
        await writer.writeFrom(plaintext);
        completedChunks.add(chunkIndex);
        current = current.copyWith(
          completedChunks: completedChunks.toList()..sort(),
          status: AttachmentTransferStatus.downloading.name,
          lastError: null,
          downloadTargetPath: targetFile.path,
        );
        await _emitSession(current);
      }
    } finally {
      await writer.close();
    }
    final digest = await crypto.sha256.bind(targetFile.openRead()).first;
    if (current.plaintextSha256.isNotEmpty &&
        digest.toString() != current.plaintextSha256) {
      throw ApiException(
        'Downloaded attachment integrity check failed.',
        code: 'attachment_integrity_failed',
      );
    }
    await _emitSession(
      current.copyWith(
        status: AttachmentTransferStatus.completed.name,
        completedChunks: completedChunks.toList()..sort(),
        downloadTargetPath: targetFile.path,
      ),
    );
    return targetFile.path;
  }

  Future<_StoredTransferSession> _guardTransferLoop(String localId) async {
    final current = await _sessionStore._readByLocalId(localId);
    if (current == null) {
      throw ApiException(
        'Transfer was cancelled.',
        code: 'attachment_transfer_cancelled',
        isRetryable: true,
      );
    }
    if (current.status == AttachmentTransferStatus.paused.name) {
      throw ApiException(
        'Transfer paused.',
        code: 'attachment_transfer_paused',
        isRetryable: true,
      );
    }
    return current;
  }

  Future<void> _emitSession(_StoredTransferSession session) async {
    await _sessionStore._upsert(session);
    await _refreshTransfers();
  }

  Future<void> _refreshTransfers() async {
    final sessions = await _sessionStore._readAll();
    transfers.value = sessions
        .map(
          (session) => AttachmentTransferState(
            localId: session.localId,
            conversationId: session.conversationId,
            direction: session.direction == AttachmentTransferDirection.download.name
                ? AttachmentTransferDirection.download
                : AttachmentTransferDirection.upload,
            status: AttachmentTransferStatus.values.firstWhere(
              (item) => item.name == session.status,
              orElse: () => AttachmentTransferStatus.queued,
            ),
            filename: session.filename,
            progress: AttachmentTransferProgress(
              completedChunks: session.completedChunks.length,
              totalChunks: session.totalChunks,
            ),
            attachmentId: session.attachmentId,
            error: session.lastError,
            localPath: session.downloadTargetPath ?? session.localSourcePath,
          ),
        )
        .toList()
      ..sort((a, b) => a.filename.compareTo(b.filename));
  }
}
