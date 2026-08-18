part of 'chat_facade.dart';

mixin _ChatFacadeAttachments on _ChatFacadeBase {
  Future<List<AttachmentTransferState>> loadAttachmentTransfers() async {
    final transferFacade = _attachmentTransferFacade;
    if (transferFacade == null) {
      return const [];
    }
    return transferFacade.loadTransfers();
  }

  Future<void> pauseAttachmentTransfer(String localId) async {
    await _attachmentTransferFacade?.pauseTransfer(localId);
  }

  Future<AttachmentTransferState?> resumeAttachmentTransfer({
    required String localId,
    required Conversation conversation,
    required int currentUserId,
  }) async {
    final transferFacade = _attachmentTransferFacade;
    if (transferFacade == null) {
      return null;
    }
    final resumed = await transferFacade.resumeTransfer(localId);
    if (resumed == null ||
        resumed.direction != AttachmentTransferDirection.upload) {
      return resumed;
    }
    final marker = ':attachment:';
    final markerIndex = localId.indexOf(marker);
    if (markerIndex <= 0) return resumed;
    await _outgoingMessageService.retryMessage(
      conversation: conversation,
      currentUserId: currentUserId,
      clientMessageId: localId.substring(0, markerIndex),
      usersById: _usersById,
      refreshUsers: _refreshUsersForSecureSend,
      persistConversation: _persistConversation,
    );
    return resumed;
  }

  Future<void> cancelAttachmentTransfer(String localId) async {
    await _attachmentTransferFacade?.cancelTransfer(localId);
  }

  Future<void> clearCompletedAttachmentTransfer(String localId) async {
    await _attachmentTransferFacade?.clearCompletedTransfer(localId);
  }

  Future<String> downloadAttachment({
    required int currentUserId,
    required Conversation conversation,
    required ChatAttachment attachment,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    if (attachment.cipherVersion == 'attachment:v2' ||
        attachment.cipherVersion == 'attachment:v3') {
      final descriptor = await _remoteDataSource.fetchAttachmentDescriptor(
        attachment.id,
      );
      final request = ChatCryptoRequest(
        currentUserId: currentUserId,
        conversation: conversation,
        usersById: _usersById,
        messageId: 'attachment-download:${attachment.id}',
      );
      final encryptionDescriptor = await _cryptoService
          .decryptAttachmentKeyWrap(
            request: request,
            wrappedDescriptor: descriptor.fileKeyWrap,
          );
      if (encryptionDescriptor.cipherVersion != descriptor.cipherVersion) {
        throw StateError('Attachment cipher descriptor does not match data.');
      }
      final cryptoAdapter = switch (descriptor.cipherVersion) {
        'attachment:v3' => SdkV3AttachmentCryptoService(),
        'attachment:v2' => SdkV2AttachmentCryptoService(),
        _ => throw StateError('Unsupported attachment cipher version.'),
      };
      if (descriptor.chunkSize <= 0 || descriptor.plaintextSize <= 0) {
        throw StateError('Encrypted attachment manifest is incomplete.');
      }
      final totalChunks =
          (descriptor.plaintextSize + descriptor.chunkSize - 1) ~/
          descriptor.chunkSize;
      final transferLocalId = 'download:${descriptor.id}';
      await _attachmentTransferFacade?.beginDownload(
        localId: transferLocalId,
        conversationId: conversation.id,
        filename: descriptor.filename,
        totalChunks: totalChunks,
        attachmentId: descriptor.id,
      );
      final builder = BytesBuilder(copy: false);
      try {
        for (var chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
          await _attachmentTransferFacade?.throwIfPaused(transferLocalId);
          final ciphertext = await _remoteDataSource.downloadAttachmentChunk(
            attachmentId: descriptor.id,
            chunkIndex: chunkIndex,
          );
          builder.add(
            await cryptoAdapter.decryptChunk(
              ciphertext: ciphertext,
              descriptor: encryptionDescriptor,
              chunkIndex: chunkIndex,
            ),
          );
          await _attachmentTransferFacade?.updateDownloadProgress(
            localId: transferLocalId,
            completedChunks: chunkIndex + 1,
            totalChunks: totalChunks,
          );
        }
      } catch (error) {
        if (error is! AttachmentTransferPausedException) {
          await _attachmentTransferFacade?.failTransfer(transferLocalId, error);
        }
        rethrow;
      }
      final bytes = builder.takeBytes();
      if (bytes.length != descriptor.plaintextSize ||
          (descriptor.plaintextSha256.isNotEmpty &&
              crypto.sha256.convert(bytes).toString().toLowerCase() !=
                  descriptor.plaintextSha256.toLowerCase())) {
        throw StateError('Encrypted attachment integrity check failed.');
      }
      final transfer = await _attachmentTransferFacade?.saveDirectDownload(
        attachment: descriptor,
        bytes: bytes,
      );
      if (transfer != null) return transfer;
      throw StateError('Attachment download storage is not configured.');
    }
    final transferLocalId = 'download:${attachment.id}';
    await _attachmentTransferFacade?.beginDownload(
      localId: transferLocalId,
      conversationId: conversation.id,
      filename: attachment.filename,
      totalChunks: 1,
      attachmentId: attachment.id,
    );
    late final List<int> bytes;
    try {
      await _attachmentTransferFacade?.throwIfPaused(transferLocalId);
      bytes = await _remoteDataSource.downloadAttachmentFile(attachment.id);
      await _attachmentTransferFacade?.updateDownloadProgress(
        localId: transferLocalId,
        completedChunks: 1,
        totalChunks: 1,
      );
    } catch (error) {
      if (error is! AttachmentTransferPausedException) {
        await _attachmentTransferFacade?.failTransfer(transferLocalId, error);
      }
      rethrow;
    }
    final transfer = await _attachmentTransferFacade?.saveDirectDownload(
      attachment: attachment,
      bytes: bytes,
    );
    if (transfer != null) return transfer;
    throw StateError('Attachment download storage is not configured.');
  }
}
