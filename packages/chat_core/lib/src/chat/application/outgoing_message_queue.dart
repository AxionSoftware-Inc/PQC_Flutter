part of 'chat_services.dart';

// Queueing and retry policy owns the durable outbox lifecycle.
// ignore_for_file: annotate_overrides

mixin _OutgoingMessageQueue on _OutgoingMessageServiceBase {
  Future<ChatMessage> sendMessage({
    required SendMessageCommand command,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation)
    persistConversation,
  }) async {
    final now = DateTime.now().toUtc();
    final clientMessageId =
        '${command.conversation.id}_${command.currentUserId}_${now.microsecondsSinceEpoch}';
    final currentUser = usersById[command.currentUserId];
    final queued = QueuedOutgoingMessage(
      clientMessageId: clientMessageId,
      conversationId: command.conversation.id,
      senderId: command.currentUserId,
      senderName: currentUser?.displayName ?? 'You',
      plaintext: command.text,
      messageType: command.messageType,
      attachments: command.attachments,
      createdAt: now,
      deliveryState: MessageDeliveryState.pending,
    );
    void emit(
      SendPipelineStage stage,
      SendPipelineStepStatus status, [
      String? detail,
    ]) {
      command.onProgress?.call(
        SendPipelineUpdate(
          clientMessageId: clientMessageId,
          stage: stage,
          status: status,
          detail: detail,
        ),
      );
    }

    emit(SendPipelineStage.localQueue, SendPipelineStepStatus.running);
    await outboxStore.upsert(queued);
    emit(
      SendPipelineStage.localQueue,
      SendPipelineStepStatus.succeeded,
      'Message stored safely in the local outbox.',
    );

    try {
      final sent = await _sendQueuedMessage(
        queued,
        conversation: command.conversation,
        currentUserId: command.currentUserId,
        usersById: usersById,
        refreshUsers: refreshUsers,
        persistConversation: persistConversation,
        onProgress: command.onProgress,
      );
      await outboxStore.remove(clientMessageId);
      return sent;
    } on ApiException catch (error) {
      final state = error.isRetryable
          ? MessageDeliveryState.failedRetryable
          : MessageDeliveryState.failedPermanent;
      await outboxStore.upsert(
        queued.copyWith(
          retryCount: queued.retryCount + (error.isRetryable ? 1 : 0),
          nextRetryAt: error.isRetryable
              ? DateTime.now().toUtc().add(
                  Duration(seconds: (queued.retryCount + 1) * 2),
                )
              : null,
          deliveryState: state,
          failureReason: error.message,
        ),
      );
      return queued
          .copyWith(deliveryState: state, failureReason: error.message)
          .toChatMessage();
    } on AttachmentTransferPausedException catch (error) {
      await outboxStore.upsert(
        queued.copyWith(
          deliveryState: MessageDeliveryState.failedRetryable,
          nextRetryAt: null,
          failureReason: error.toString(),
        ),
      );
      return queued
          .copyWith(
            deliveryState: MessageDeliveryState.failedRetryable,
            failureReason: error.toString(),
          )
          .toChatMessage();
    } catch (error) {
      final reason = error.toString();
      await outboxStore.upsert(
        queued.copyWith(
          deliveryState: MessageDeliveryState.failedPermanent,
          failureReason: reason,
        ),
      );
      return queued
          .copyWith(
            deliveryState: MessageDeliveryState.failedPermanent,
            failureReason: reason,
          )
          .toChatMessage();
    }
  }

  Future<void> flushPendingMessages({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation)
    persistConversation,
    bool includeAttachments = false,
  }) async {
    final pending = await outboxStore.readForConversation(conversation.id);
    for (final item in pending) {
      // File sends are explicit user actions. Retrying them automatically on
      // every login/chat refresh can replay large uploads and block history.
      if (!includeAttachments && item.attachments.isNotEmpty) {
        continue;
      }
      if (item.deliveryState == MessageDeliveryState.failedPermanent) {
        continue;
      }
      if (item.nextRetryAt != null &&
          item.nextRetryAt!.isAfter(DateTime.now().toUtc())) {
        continue;
      }
      try {
        await _sendQueuedMessage(
          item.copyWith(deliveryState: MessageDeliveryState.pending),
          conversation: conversation,
          currentUserId: currentUserId,
          usersById: usersById,
          refreshUsers: refreshUsers,
          persistConversation: persistConversation,
        );
        await outboxStore.remove(item.clientMessageId);
      } on ApiException catch (error) {
        await outboxStore.upsert(
          item.copyWith(
            retryCount: item.retryCount + (error.isRetryable ? 1 : 0),
            nextRetryAt: error.isRetryable
                ? DateTime.now().toUtc().add(
                    Duration(seconds: (item.retryCount + 1) * 2),
                  )
                : null,
            deliveryState: error.isRetryable
                ? MessageDeliveryState.failedRetryable
                : MessageDeliveryState.failedPermanent,
            failureReason: error.message,
          ),
        );
      }
    }
  }

  Future<void> retryMessage({
    required Conversation conversation,
    required int currentUserId,
    required String clientMessageId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation)
    persistConversation,
  }) async {
    final queued = await outboxStore.readForConversation(conversation.id);
    final target = queued.where(
      (item) => item.clientMessageId == clientMessageId,
    );
    if (target.isEmpty) {
      return;
    }
    await outboxStore.upsert(
      target.first.copyWith(
        retryCount: 0,
        nextRetryAt: null,
        deliveryState: MessageDeliveryState.pending,
        failureReason: null,
      ),
    );
    await flushPendingMessages(
      conversation: conversation,
      currentUserId: currentUserId,
      usersById: usersById,
      refreshUsers: refreshUsers,
      persistConversation: persistConversation,
      includeAttachments: true,
    );
  }
}
