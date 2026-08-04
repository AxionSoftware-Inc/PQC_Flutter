import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/features/chat/application/chat_controllers.dart';
import 'package:pqc_chat_app/core/models/chat_message.dart';

void main() {
  test('server confirmation replaces the matching local outbox message', () {
    final createdAt = DateTime.utc(2026, 8, 4, 12);
    final pending = ChatMessage(
      id: -1,
      conversationId: 7,
      senderId: 3,
      senderName: 'Me',
      body: 'hello',
      createdAt: createdAt,
      clientMessageId: '7_3_123',
      deliveryState: MessageDeliveryState.pending,
    );
    final confirmed = pending.copyWith(
      id: 42,
      body: 'encrypted-body-from-server',
      deliveryState: MessageDeliveryState.sent,
    );

    final merged = mergeChatTimeline([pending], [confirmed]);

    expect(merged, hasLength(1));
    expect(merged.single.id, 42);
    expect(merged.single.deliveryState, MessageDeliveryState.sent);
  });
}
