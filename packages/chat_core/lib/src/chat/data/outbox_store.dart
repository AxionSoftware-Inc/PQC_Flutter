// ignore_for_file: implementation_imports

import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';
import 'package:crypto_core/src/models/chat_message.dart';
import 'package:crypto_core/src/core/storage/local_data_protector.dart';

class QueuedOutgoingMessage {
  const QueuedOutgoingMessage({
    required this.clientMessageId,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.plaintext,
    this.encryptedPayload = '',
    required this.createdAt,
    this.retryCount = 0,
    this.nextRetryAt,
    required this.deliveryState,
    this.failureReason,
  });

  final String clientMessageId;
  final int conversationId;
  final int senderId;
  final String senderName;
  final String plaintext;
  final String encryptedPayload;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? nextRetryAt;
  final MessageDeliveryState deliveryState;
  final String? failureReason;

  Map<String, dynamic> toJson() {
    return {
      'client_message_id': clientMessageId,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'sender_name': senderName,
      'plaintext': plaintext,
      'encrypted_payload': encryptedPayload,
      'created_at': createdAt.toIso8601String(),
      'retry_count': retryCount,
      'next_retry_at': nextRetryAt?.toIso8601String(),
      'delivery_state': switch (deliveryState) {
        MessageDeliveryState.pending => 'pending',
        MessageDeliveryState.sent => 'sent',
        MessageDeliveryState.failedRetryable => 'failed-retryable',
        MessageDeliveryState.failedPermanent => 'failed-permanent',
      },
      'failure_reason': failureReason,
    };
  }

  factory QueuedOutgoingMessage.fromJson(Map<String, dynamic> json) {
    return QueuedOutgoingMessage(
      clientMessageId: json['client_message_id'] as String,
      conversationId: json['conversation_id'] as int,
      senderId: json['sender_id'] as int,
      senderName: json['sender_name'] as String,
      plaintext: json['plaintext'] as String,
      encryptedPayload: json['encrypted_payload'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      retryCount: json['retry_count'] as int? ?? 0,
      nextRetryAt: json['next_retry_at'] == null
          ? null
          : DateTime.tryParse(json['next_retry_at'] as String),
      deliveryState: switch (json['delivery_state'] as String? ?? 'pending') {
        'failed-retryable' => MessageDeliveryState.failedRetryable,
        'failed-permanent' => MessageDeliveryState.failedPermanent,
        'sent' => MessageDeliveryState.sent,
        _ => MessageDeliveryState.pending,
      },
      failureReason: json['failure_reason'] as String?,
    );
  }

  QueuedOutgoingMessage copyWith({
    String? encryptedPayload,
    int? retryCount,
    DateTime? nextRetryAt,
    MessageDeliveryState? deliveryState,
    String? failureReason,
  }) {
    return QueuedOutgoingMessage(
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      plaintext: plaintext,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      deliveryState: deliveryState ?? this.deliveryState,
      failureReason: failureReason ?? this.failureReason,
    );
  }

  ChatMessage toChatMessage() {
    return ChatMessage(
      id: -createdAt.microsecondsSinceEpoch,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      body: plaintext,
      createdAt: createdAt,
      clientMessageId: clientMessageId,
      deliveryState: deliveryState,
      failureReason: failureReason,
    );
  }
}

class OutboxStore {
  static const _storageKey = 'queued_outgoing_messages';
  static const _legacyImportedKey = 'queued_outgoing_messages_imported';

  OutboxStore({AppDatabase? database, LocalDataProtector? localDataProtector})
    : _database = database ?? AppDatabase(),
      _localDataProtector = localDataProtector ?? LocalDataProtector();

  final AppDatabase _database;
  final LocalDataProtector _localDataProtector;

  Future<List<QueuedOutgoingMessage>> readAll() async {
    await _importLegacyIfNeeded();
    final rows = await _database.readAllQueuedMessages();
    final messages = <QueuedOutgoingMessage>[];
    for (final row in rows) {
      messages.add(
        QueuedOutgoingMessage(
          clientMessageId: row.clientMessageId,
          conversationId: row.conversationId,
          senderId: row.senderId,
          senderName: row.senderName,
          plaintext: await _localDataProtector.unprotect(row.plaintext),
          encryptedPayload: row.encryptedPayload,
          createdAt: row.createdAt,
          retryCount: row.retryCount,
          nextRetryAt: row.nextRetryAt,
          deliveryState: _deliveryStateFromStored(row.deliveryState),
          failureReason: row.failureReason,
        ),
      );
    }
    return messages;
  }

  Future<List<QueuedOutgoingMessage>> readForConversation(
    int conversationId,
  ) async {
    final items = await readAll();
    return items
        .where((item) => item.conversationId == conversationId)
        .toList();
  }

  Future<void> upsert(QueuedOutgoingMessage message) async {
    await _database.upsertQueuedMessage(
      QueuedOutgoingMessagesTableCompanion(
        clientMessageId: drift.Value(message.clientMessageId),
        conversationId: drift.Value(message.conversationId),
        senderId: drift.Value(message.senderId),
        senderName: drift.Value(message.senderName),
        plaintext: drift.Value(
          await _localDataProtector.protect(message.plaintext),
        ),
        encryptedPayload: drift.Value(message.encryptedPayload),
        createdAt: drift.Value(message.createdAt),
        retryCount: drift.Value(message.retryCount),
        nextRetryAt: drift.Value(message.nextRetryAt),
        deliveryState: drift.Value(
          _deliveryStateToStored(message.deliveryState),
        ),
        failureReason: drift.Value(message.failureReason),
      ),
    );
  }

  Future<void> remove(String clientMessageId) async {
    await _database.removeQueuedMessage(clientMessageId);
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    await _database.clearQueuedMessages();
  }

  Future<void> _importLegacyIfNeeded() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_legacyImportedKey) == true) {
      return;
    }
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      await preferences.setBool(_legacyImportedKey, true);
      return;
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    for (final item in decoded) {
      final message = QueuedOutgoingMessage.fromJson(
        item as Map<String, dynamic>,
      );
      await _database.upsertQueuedMessage(
        QueuedOutgoingMessagesTableCompanion(
          clientMessageId: drift.Value(message.clientMessageId),
          conversationId: drift.Value(message.conversationId),
          senderId: drift.Value(message.senderId),
          senderName: drift.Value(message.senderName),
          plaintext: drift.Value(
            await _localDataProtector.protect(message.plaintext),
          ),
          encryptedPayload: drift.Value(message.encryptedPayload),
          createdAt: drift.Value(message.createdAt),
          retryCount: drift.Value(message.retryCount),
          nextRetryAt: drift.Value(message.nextRetryAt),
          deliveryState: drift.Value(
            _deliveryStateToStored(message.deliveryState),
          ),
          failureReason: drift.Value(message.failureReason),
        ),
      );
    }
    await preferences.setBool(_legacyImportedKey, true);
    await preferences.remove(_storageKey);
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
      case 'sent':
        return MessageDeliveryState.sent;
      case 'pending':
      default:
        return MessageDeliveryState.pending;
    }
  }
}
