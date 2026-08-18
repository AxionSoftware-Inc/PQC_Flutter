part of 'chat_services.dart';

// Attachment methods implement the base contract.
// ignore_for_file: annotate_overrides

mixin _OutgoingMessageAttachments on _OutgoingMessageServiceBase {
  Future<ChatAttachment> _uploadEncryptedAttachment({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required String clientMessageId,
    required int attachmentIndex,
    required PendingAttachmentUpload attachment,
    required String cipherVersion,
  }) async {
    final cryptoAdapter = switch (cipherVersion) {
      'attachment:v3' => SdkV3AttachmentCryptoService(),
      'attachment:v2' => SdkV2AttachmentCryptoService(),
      _ => throw ApiException(
        'Unsupported attachment cipher version: $cipherVersion',
        code: 'attachment_cipher_unsupported',
        isRetryable: false,
      ),
    };
    File? temporaryFile;
    final sourceFile = await _materializeAttachmentFile(
      attachment,
      onTemporaryFile: (file) => temporaryFile = file,
    );
    try {
      final analysis = await cryptoAdapter.analyzeFile(
        file: sourceFile,
        chunkSize: _OutgoingMessageServiceBase._attachmentChunkSize,
      );
      if (analysis.plaintextSize <= 0 || analysis.totalChunks <= 0) {
        throw ApiException(
          'Attachment file is empty.',
          code: 'attachment_source_empty',
          isRetryable: false,
        );
      }
      final transferLocalId = '$clientMessageId:attachment:$attachmentIndex';
      await attachmentTransferFacade?.beginUpload(
        localId: transferLocalId,
        conversationId: conversation.id,
        filename: attachment.filename,
        totalChunks: analysis.totalChunks,
      );
      final descriptor = cryptoAdapter.generateDescriptor();
      final keyWrap = await cryptoService.encryptAttachmentKeyWrap(
        request: ChatCryptoRequest(
          currentUserId: currentUserId,
          conversation: conversation,
          usersById: usersById,
          messageId:
              'attachment-key:$clientMessageId:$attachmentIndex:${attachment.filename}',
          senderId: currentUserId,
        ),
        descriptor: descriptor,
      );
      final manifest = EncryptedAttachmentManifest(
        filename: attachment.filename,
        mimeType: attachment.mimeType,
        cipherVersion: descriptor.cipherVersion,
        chunkSize: _OutgoingMessageServiceBase._attachmentChunkSize,
        plaintextSize: analysis.plaintextSize,
        ciphertextSize: analysis.ciphertextSize,
        totalChunks: analysis.totalChunks,
        plaintextSha256: analysis.plaintextSha256,
        manifestSha256: '',
        fileKeyWrap: keyWrap,
        conversationEpochId: descriptor.conversationEpochId,
        recoveryManifestSequence: descriptor.manifestSequence,
      );
      final manifestSha256 = await cryptoAdapter.buildManifestSha256(manifest);
      final session = await remoteDataSource.createAttachmentSession(
        conversation.id,
        filename: manifest.filename,
        mimeType: manifest.mimeType,
        cipherVersion: manifest.cipherVersion,
        plaintextSize: manifest.plaintextSize,
        ciphertextSize: manifest.ciphertextSize,
        chunkSize: manifest.chunkSize,
        totalChunks: manifest.totalChunks,
        plaintextSha256: manifest.plaintextSha256,
        manifestSha256: manifestSha256,
        fileKeyWrap: manifest.fileKeyWrap,
        conversationEpochId: manifest.conversationEpochId,
        recoveryManifestSequence: manifest.recoveryManifestSequence,
      );
      final sessionId = session['session_id'] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        throw ApiException(
          'Attachment session did not return an id.',
          code: 'attachment_session_id_missing',
          isRetryable: false,
        );
      }
      for (
        var chunkIndex = 0;
        chunkIndex < analysis.totalChunks;
        chunkIndex++
      ) {
        await attachmentTransferFacade?.throwIfPaused(transferLocalId);
        final encrypted = await cryptoAdapter.encryptChunk(
          file: sourceFile,
          descriptor: descriptor,
          chunkSize: _OutgoingMessageServiceBase._attachmentChunkSize,
          chunkIndex: chunkIndex,
        );
        await remoteDataSource.uploadAttachmentChunk(
          sessionId: sessionId,
          chunkIndex: chunkIndex,
          ciphertext: encrypted.ciphertext,
        );
        await attachmentTransferFacade?.updateUploadProgress(
          localId: transferLocalId,
          completedChunks: chunkIndex + 1,
          totalChunks: analysis.totalChunks,
        );
      }
      final uploaded = await remoteDataSource.completeAttachmentSession(
        sessionId: sessionId,
        manifestSha256: manifestSha256,
      );
      await attachmentTransferFacade?.completeUpload(
        transferLocalId,
        attachmentId: uploaded.id,
      );
      return uploaded;
    } catch (error) {
      final transferLocalId = '$clientMessageId:attachment:$attachmentIndex';
      if (error is! AttachmentTransferPausedException) {
        await attachmentTransferFacade?.failTransfer(transferLocalId, error);
      }
      rethrow;
    } finally {
      if (temporaryFile != null) {
        try {
          await temporaryFile!.delete();
          await temporaryFile!.parent.delete(recursive: true);
        } catch (_) {
          // A failed cleanup must not mask the upload result.
        }
      }
    }
  }

  Future<File> _materializeAttachmentFile(
    PendingAttachmentUpload attachment, {
    required void Function(File file) onTemporaryFile,
  }) async {
    final filePath = attachment.filePath;
    if (filePath != null && filePath.trim().isNotEmpty) {
      final file = File(filePath);
      if (!await file.exists()) {
        throw ApiException(
          'Attachment source file does not exist.',
          code: 'attachment_source_missing',
          isRetryable: false,
        );
      }
      return file;
    }
    final bytes = attachment.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw ApiException(
        'Attachment source is empty.',
        code: 'attachment_source_empty',
        isRetryable: false,
      );
    }
    final directory = await Directory.systemTemp.createTemp('pqc-attachment-');
    final file = File('${directory.path}/upload.bin');
    await file.writeAsBytes(bytes, flush: true);
    onTemporaryFile(file);
    return file;
  }
}
