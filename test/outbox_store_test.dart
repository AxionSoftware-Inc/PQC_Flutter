import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/database/app_database.dart';
import 'package:pqc_chat_app/core/models/chat_message.dart';
import 'package:pqc_chat_app/core/storage/local_data_protector.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';
import 'package:pqc_chat_app/features/chat/data/outbox_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('outbox store persists and removes queued messages', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.inMemory();
    final protector = LocalDataProtector(secretStore: _MemorySecretStore());
    final store = OutboxStore(
      database: database,
      localDataProtector: protector,
    );
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
    final rawRows = await database.readAllQueuedMessages();
    await store.remove('msg-1');
    final cleared = await store.readForConversation(1);

    expect(saved.single.clientMessageId, 'msg-1');
    expect(rawRows.single.plaintext, isNot('hello'));
    expect(cleared, isEmpty);
    await database.close();
  });

  test(
    'outbox clear does not wipe stored conversations and messages',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase.inMemory();
      final protector = LocalDataProtector(secretStore: _MemorySecretStore());
      final store = OutboxStore(
        database: database,
        localDataProtector: protector,
      );

      await database.upsertConversation(
        ConversationsTableCompanion(
          id: const drift.Value(1),
          type: const drift.Value('private'),
          title: const drift.Value('Alice'),
          lastMessagePreview: const drift.Value('preview'),
          updatedAt: drift.Value(DateTime.parse('2026-07-11T00:00:00Z')),
          createdAt: drift.Value(DateTime.parse('2026-07-11T00:00:00Z')),
        ),
      );
      await database.upsertMessage(
        MessagesTableCompanion(
          id: const drift.Value(1),
          conversationId: const drift.Value(1),
          senderId: const drift.Value(1),
          senderName: const drift.Value('Alice'),
          plaintextBody: const drift.Value('hello'),
          createdAt: drift.Value(DateTime.parse('2026-07-11T00:00:00Z')),
        ),
      );
      await store.upsert(
        QueuedOutgoingMessage(
          clientMessageId: 'msg-1',
          conversationId: 1,
          senderId: 1,
          senderName: 'Alice',
          plaintext: 'queued',
          createdAt: DateTime.parse('2026-07-11T00:00:01Z'),
          deliveryState: MessageDeliveryState.pending,
        ),
      );

      await store.clear();

      final conversations = await database.readConversations();
      final messages = await database.readMessagesForConversation(1);
      final queued = await database.readAllQueuedMessages();

      expect(conversations, isNotEmpty);
      expect(messages, isNotEmpty);
      expect(queued, isEmpty);
      await database.close();
    },
  );
}

class _MemorySecretStore extends LocalSecretStore {
  _MemorySecretStore() : super();

  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
