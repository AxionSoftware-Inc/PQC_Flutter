import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/models/chat_message.dart';
import 'package:pqc_chat_app/features/chat/data/outbox_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('outbox store persists and removes queued messages', () async {
    SharedPreferences.setMockInitialValues({});
    final store = OutboxStore();
    final queued = QueuedOutgoingMessage(
      clientMessageId: 'msg-1',
      conversationId: 1,
      senderId: 1,
      senderName: 'Alice',
      plaintext: 'hello',
      createdAt: DateTime.parse('2026-07-05T00:00:00Z'),
      deliveryState: MessageDeliveryState.pending,
    );

    await store.upsert(queued);
    final saved = await store.readForConversation(1);
    await store.remove('msg-1');
    final cleared = await store.readForConversation(1);

    expect(saved.single.clientMessageId, 'msg-1');
    expect(cleared, isEmpty);
  });
}
