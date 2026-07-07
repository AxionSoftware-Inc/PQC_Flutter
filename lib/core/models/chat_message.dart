enum MessageDeliveryState { pending, sent, failedRetryable, failedPermanent }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
    this.clientMessageId = '',
    this.deliveryState = MessageDeliveryState.sent,
    this.failureReason,
  });

  final int id;
  final int conversationId;
  final int senderId;
  final String senderName;
  final String body;
  final DateTime createdAt;
  final String clientMessageId;
  final MessageDeliveryState deliveryState;
  final String? failureReason;

  bool get isPending => deliveryState == MessageDeliveryState.pending;
  bool get canRetry => deliveryState == MessageDeliveryState.failedRetryable;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      conversationId: json['conversation_id'] as int,
      senderId: json['sender_id'] as int,
      senderName: json['sender_name'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      clientMessageId: json['client_message_id'] as String? ?? '',
      deliveryState: _deliveryStateFromJson(
        json['delivery_state'] as String? ?? 'sent',
      ),
    );
  }

  ChatMessage copyWith({
    int? id,
    int? conversationId,
    int? senderId,
    String? senderName,
    String? body,
    DateTime? createdAt,
    String? clientMessageId,
    MessageDeliveryState? deliveryState,
    String? failureReason,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      deliveryState: deliveryState ?? this.deliveryState,
      failureReason: failureReason ?? this.failureReason,
    );
  }

  static MessageDeliveryState _deliveryStateFromJson(String value) {
    switch (value) {
      case 'pending':
        return MessageDeliveryState.pending;
      case 'failed-retryable':
        return MessageDeliveryState.failedRetryable;
      case 'failed-permanent':
        return MessageDeliveryState.failedPermanent;
      case 'sent':
      default:
        return MessageDeliveryState.sent;
    }
  }
}
