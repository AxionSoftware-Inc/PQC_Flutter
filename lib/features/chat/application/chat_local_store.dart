import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../../core/database/app_database.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/storage/local_data_protector.dart';

class ChatLocalStore {
  ChatLocalStore({
    required this._database,
    required this._localDataProtector,
  });

  final AppDatabase _database;
  final LocalDataProtector _localDataProtector;

  Future<List<ConversationsTableData>> readVisibleConversationRows(
    int activeWorkspaceId,
  ) async {
    if (activeWorkspaceId <= 0) {
      return _database.readConversations();
    }
    final allRows = await _database.readConversations();
    final visible = allRows.where((row) {
      return row.workspaceId == activeWorkspaceId || row.workspaceId == 0;
    }).toList();
    if (visible.isNotEmpty) {
      return visible;
    }
    return allRows;
  }

  Future<void> persistConversation({
    required Conversation conversation,
    required int activeWorkspaceId,
  }) async {
    final effectiveWorkspaceId = conversation.workspaceId > 0
        ? conversation.workspaceId
        : activeWorkspaceId;
    await _database.upsertConversation(
      ConversationsTableCompanion(
        id: drift.Value(conversation.id),
        workspaceId: drift.Value(effectiveWorkspaceId),
        type: drift.Value(conversation.type),
        title: drift.Value(conversation.title),
        lastMessagePreview: drift.Value(
          await _localDataProtector.protect(conversation.lastMessagePreview),
        ),
        updatedAt: drift.Value(conversation.updatedAt),
        createdAt: drift.Value(conversation.createdAt),
      ),
    );
  }

  Future<Conversation> mapConversationRow({
    required ConversationsTableData row,
    required Conversation? knownConversation,
  }) async {
    return Conversation(
      id: row.id,
      workspaceId: row.workspaceId,
      type: row.type,
      title: row.title,
      participantIds: knownConversation?.participantIds ?? const [],
      lastMessagePreview: await _localDataProtector.unprotect(
        row.lastMessagePreview,
      ),
      updatedAt: row.updatedAt,
      createdAt: row.createdAt,
    );
  }

  Future<List<MessagesTableData>> readMessageRows(int conversationId) {
    return _database.readMessagesForConversation(conversationId);
  }

  Future<MessagesTableData> unprotectMessageRow(MessagesTableData row) async {
    return row.copyWith(
      plaintextBody: await _localDataProtector.unprotect(row.plaintextBody),
    );
  }

  Future<void> persistMessage({
    required ChatMessage decoded,
    required String encryptedBody,
  }) async {
    await _database.upsertMessage(
      MessagesTableCompanion(
        id: drift.Value(decoded.id),
        conversationId: drift.Value(decoded.conversationId),
        senderId: drift.Value(decoded.senderId),
        senderName: drift.Value(decoded.senderName),
        plaintextBody: drift.Value(
          await _localDataProtector.protect(decoded.body),
        ),
        encryptedBody: drift.Value(encryptedBody),
        attachmentsJson: drift.Value(_encodeAttachments(decoded.attachments)),
        messageType: drift.Value(decoded.messageType),
        attachmentCount: drift.Value(decoded.attachmentCount),
        clientMessageId: drift.Value(decoded.clientMessageId),
        deliveryState: drift.Value(_deliveryStateToStored(decoded.deliveryState)),
        failureReason: drift.Value(decoded.failureReason),
        isPending: const drift.Value(false),
        createdAt: drift.Value(decoded.createdAt),
      ),
    );
  }

  Future<void> repairPlaintext({
    required MessagesTableData row,
    required String plaintext,
  }) async {
    await _database.upsertMessage(
      MessagesTableCompanion(
        id: drift.Value(row.id),
        conversationId: drift.Value(row.conversationId),
        senderId: drift.Value(row.senderId),
        senderName: drift.Value(row.senderName),
        plaintextBody: drift.Value(
          await _localDataProtector.protect(plaintext),
        ),
        encryptedBody: drift.Value(row.encryptedBody),
        attachmentsJson: drift.Value(row.attachmentsJson),
        messageType: drift.Value(row.messageType),
        attachmentCount: drift.Value(row.attachmentCount),
        clientMessageId: drift.Value(row.clientMessageId),
        deliveryState: drift.Value(row.deliveryState),
        failureReason: drift.Value(row.failureReason),
        isPending: drift.Value(row.isPending),
        createdAt: drift.Value(row.createdAt),
      ),
    );
  }

  Future<List<ChatMessage>> readMessages(int conversationId) async {
    final rows = await _database.readMessagesForConversation(conversationId);
    final mapped = <ChatMessage>[];
    for (final row in rows) {
      mapped.add(await mapMessageRow(row));
    }
    return mapped;
  }

  Future<ChatMessage> mapMessageRow(MessagesTableData row) async {
    return ChatMessage(
      id: row.id,
      conversationId: row.conversationId,
      senderId: row.senderId,
      senderName: row.senderName,
      body: await _localDataProtector.unprotect(row.plaintextBody),
      createdAt: row.createdAt,
      attachments: _decodeAttachments(row.attachmentsJson),
      messageType: row.messageType,
      attachmentCount: row.attachmentCount,
      clientMessageId: row.clientMessageId,
      deliveryState: _deliveryStateFromStored(row.deliveryState),
      failureReason: row.failureReason,
    );
  }

  Future<void> upsertSyncState({
    required int conversationId,
    required int lastMessageId,
  }) {
    return _database.upsertSyncState(
      ConversationSyncStateTableCompanion(
        conversationId: drift.Value(conversationId),
        lastMessageId: drift.Value(lastMessageId),
        lastSyncedAt: drift.Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<ConversationSyncStateTableData?> readSyncState(int conversationId) {
    return _database.readSyncState(conversationId);
  }

  String encodeAttachments(List<ChatAttachment> attachments) {
    return _encodeAttachments(attachments);
  }

  List<ChatAttachment> decodeAttachments(String raw) {
    return _decodeAttachments(raw);
  }

  String _deliveryStateToStored(MessageDeliveryState state) => switch (state) {
    MessageDeliveryState.pending => 'pending',
    MessageDeliveryState.sent => 'sent',
    MessageDeliveryState.failedRetryable => 'failed-retryable',
    MessageDeliveryState.failedPermanent => 'failed-permanent',
  };

  MessageDeliveryState _deliveryStateFromStored(String value) {
    switch (value) {
      case 'failed-retryable':
        return MessageDeliveryState.failedRetryable;
      case 'failed-permanent':
        return MessageDeliveryState.failedPermanent;
      case 'pending':
        return MessageDeliveryState.pending;
      case 'sent':
      default:
        return MessageDeliveryState.sent;
    }
  }

  String _encodeAttachments(List<ChatAttachment> attachments) {
    return jsonEncode(
      attachments
          .map(
            (item) => {
              'id': item.id,
              'filename': item.filename,
              'mime_type': item.mimeType,
              'size_bytes': item.sizeBytes,
              'storage_key': item.storageKey,
              'thumbnail_key': item.thumbnailKey,
              'created_at': item.createdAt?.toIso8601String(),
            },
          )
          .toList(),
    );
  }

  List<ChatAttachment> _decodeAttachments(String raw) {
    if (raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => ChatAttachment.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
