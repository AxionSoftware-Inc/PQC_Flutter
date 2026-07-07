import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/chat_message.dart';

class QueuedOutgoingMessage {
  const QueuedOutgoingMessage({
    required this.clientMessageId,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.plaintext,
    required this.createdAt,
    required this.deliveryState,
    this.failureReason,
  });

  final String clientMessageId;
  final int conversationId;
  final int senderId;
  final String senderName;
  final String plaintext;
  final DateTime createdAt;
  final MessageDeliveryState deliveryState;
  final String? failureReason;

  Map<String, dynamic> toJson() {
    return {
      'client_message_id': clientMessageId,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'sender_name': senderName,
      'plaintext': plaintext,
      'created_at': createdAt.toIso8601String(),
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
      createdAt: DateTime.parse(json['created_at'] as String),
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
    MessageDeliveryState? deliveryState,
    String? failureReason,
  }) {
    return QueuedOutgoingMessage(
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      plaintext: plaintext,
      createdAt: createdAt,
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

  Future<List<QueuedOutgoingMessage>> readAll() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => QueuedOutgoingMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<QueuedOutgoingMessage>> readForConversation(int conversationId) async {
    final items = await readAll();
    return items.where((item) => item.conversationId == conversationId).toList();
  }

  Future<void> upsert(QueuedOutgoingMessage message) async {
    final items = await readAll();
    final next = [
      ...items.where((item) => item.clientMessageId != message.clientMessageId),
      message,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await _writeAll(next);
  }

  Future<void> remove(String clientMessageId) async {
    final items = await readAll();
    await _writeAll(
      items.where((item) => item.clientMessageId != clientMessageId).toList(),
    );
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }

  Future<void> _writeAll(List<QueuedOutgoingMessage> items) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }
}
