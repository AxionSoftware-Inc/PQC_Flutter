part of 'chat_services.dart';

// Delivery owns capability checks, encryption, upload and server persistence.
// ignore_for_file: annotate_overrides

mixin _OutgoingMessageDelivery on _OutgoingMessageServiceBase {
  Future<ChatMessage> _sendQueuedMessage(
    QueuedOutgoingMessage queued, {
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation)
    persistConversation,
    SendPipelineProgress? onProgress,
  }) async {
    final inFlight = _inFlightSends[queued.clientMessageId];
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<ChatMessage> operation;
    operation = _sendQueuedMessageOnce(
      queued,
      conversation: conversation,
      currentUserId: currentUserId,
      usersById: usersById,
      refreshUsers: refreshUsers,
      persistConversation: persistConversation,
      onProgress: onProgress,
    );
    _inFlightSends[queued.clientMessageId] = operation;
    return operation.whenComplete(() {
      if (identical(_inFlightSends[queued.clientMessageId], operation)) {
        _inFlightSends.remove(queued.clientMessageId);
      }
    });
  }

  Future<ChatMessage> _sendQueuedMessageOnce(
    QueuedOutgoingMessage queued, {
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation)
    persistConversation,
    SendPipelineProgress? onProgress,
  }) async {
    void emit(
      SendPipelineStage stage,
      SendPipelineStepStatus status, [
      String? detail,
    ]) {
      onProgress?.call(
        SendPipelineUpdate(
          clientMessageId: queued.clientMessageId,
          stage: stage,
          status: status,
          detail: detail,
        ),
      );
    }

    Future<T> runStage<T>(
      SendPipelineStage stage,
      Future<T> Function() action, {
      String? successDetail,
    }) async {
      emit(stage, SendPipelineStepStatus.running);
      try {
        final result = await action();
        emit(stage, SendPipelineStepStatus.succeeded, successDetail);
        return result;
      } catch (error) {
        emit(stage, SendPipelineStepStatus.failed, error.toString());
        rethrow;
      }
    }

    final capabilities = await runStage(
      SendPipelineStage.capabilityCheck,
      _fetchCryptoProtocolCapabilities,
      successDetail: 'Server accepts the selected crypto protocol.',
    );
    try {
      await cryptoService.assertRemoteCanSend(
        isGroup: conversation.isGroup,
        remotePrefixes: conversation.isGroup
            ? capabilities.groupMessagePrefixes
            : capabilities.privateMessagePrefixes,
        readableRemotePrefixes: conversation.isGroup
            ? capabilities.readableGroupMessagePrefixes
            : capabilities.readablePrivateMessagePrefixes,
        readableGroupEnvelopePrefixes:
            capabilities.readableGroupEnvelopePrefixes,
        writableGroupEnvelopePrefixes: capabilities.groupEnvelopePrefixes,
        remoteAttachmentVersions: capabilities.attachmentCipherVersions,
        hasAttachments: queued.attachments.isNotEmpty,
      );
    } on StateError catch (error) {
      // A protocol mismatch is permanent for this queued payload. Persist it
      // as a delivery failure instead of allowing a crypto assertion to escape
      // through the UI event loop.
      throw ApiException(
        error.message,
        code: 'crypto_protocol_mismatch',
        isRetryable: false,
      );
    }
    final attachmentIds = <int>[];
    for (
      var attachmentIndex = 0;
      attachmentIndex < queued.attachments.length;
      attachmentIndex++
    ) {
      final attachment = queued.attachments[attachmentIndex];
      if (!attachment.hasUploadSource) {
        throw ApiException(
          'Attachment source is missing. Please pick the file again.',
          code: 'attachment_source_missing',
          isRetryable: false,
        );
      }
      final uploaded = await _uploadEncryptedAttachment(
        conversation: conversation,
        currentUserId: currentUserId,
        usersById: usersById,
        clientMessageId: queued.clientMessageId,
        attachmentIndex: attachmentIndex,
        attachment: attachment,
        cipherVersion: cryptoService.activeAttachmentCipherVersion(
          isGroup: conversation.isGroup,
          remoteAttachmentVersions: capabilities.attachmentCipherVersions,
        ),
      );
      attachmentIds.add(uploaded.id);
    }
    await runStage(
      SendPipelineStage.keyHealth,
      cryptoService.assertLocalKeyHealth,
      successDetail: 'Local key registry passed integrity checks.',
    );
    final payload = queued.encryptedPayload.isNotEmpty
        ? queued.encryptedPayload
        : await runStage(
            SendPipelineStage.encryption,
            () => _encryptPayloadWithUserRefresh(
              conversation: conversation,
              currentUserId: currentUserId,
              usersById: usersById,
              plaintext: queued.plaintext,
              messageId: queued.clientMessageId,
              refreshUsers: refreshUsers,
            ),
            successDetail: 'Payload encrypted and bound to this message ID.',
          );
    if (queued.encryptedPayload.isNotEmpty) {
      emit(
        SendPipelineStage.encryption,
        SendPipelineStepStatus.succeeded,
        'Previously encrypted outbox payload reused.',
      );
    }
    if (queued.encryptedPayload.isEmpty) {
      await outboxStore.upsert(queued.copyWith(encryptedPayload: payload));
    }
    final ensureDurable = onCryptoStateChanged;
    if (ensureDurable != null) {
      // Recovery protects future reinstalls, but a transient vault/network
      // outage must never turn an otherwise valid encrypted message into a
      // failed send. The outbox already retains its ciphertext locally and
      // the next lifecycle/send retries the immutable recovery snapshot.
      emit(
        SendPipelineStage.recoveryVault,
        SendPipelineStepStatus.skipped,
        'Recovery snapshot is queued after delivery.',
      );
    } else {
      emit(
        SendPipelineStage.recoveryVault,
        SendPipelineStepStatus.skipped,
        'Recovery vault is not configured.',
      );
    }
    final message = await runStage(
      SendPipelineStage.serverDelivery,
      () => remoteDataSource.sendMessage(
        conversation.id,
        payload,
        clientMessageId: queued.clientMessageId,
        messageType: attachmentIds.isEmpty ? 'text' : queued.messageType,
        attachmentIds: attachmentIds,
      ),
      successDetail: 'Server accepted and stored the encrypted message.',
    );
    final decoded = ChatMessage(
      id: message.id,
      conversationId: message.conversationId,
      senderId: message.senderId,
      senderName: message.senderName,
      body: message.senderId == currentUserId
          ? queued.plaintext
          : await _decryptPayloadWithUserRefresh(
              conversation: conversation,
              currentUserId: currentUserId,
              usersById: usersById,
              payload: message.body,
              senderId: message.senderId,
              refreshUsers: refreshUsers,
            ),
      createdAt: message.createdAt,
      messageType: message.messageType,
      attachmentCount: message.attachmentCount,
      attachments: message.attachments,
      clientMessageId: message.clientMessageId,
      deliveryState: MessageDeliveryState.sent,
    );
    await runStage(
      SendPipelineStage.localPersistence,
      () async {
        await localStore.persistMessage(
          decoded: decoded,
          encryptedBody: message.body,
        );
        await persistConversation(
          conversation.copyWith(
            lastMessagePreview: decoded.body.length > 80
                ? decoded.body.substring(0, 80)
                : decoded.body,
            updatedAt: decoded.createdAt,
          ),
        );
      },
      successDetail:
          'Encrypted payload and protected plaintext cached locally.',
    );
    if (ensureDurable != null) {
      unawaited(ensureDurable().catchError((_) {}));
    }
    emit(
      SendPipelineStage.completed,
      SendPipelineStepStatus.succeeded,
      'All send checks completed successfully.',
    );
    return decoded;
  }
}
