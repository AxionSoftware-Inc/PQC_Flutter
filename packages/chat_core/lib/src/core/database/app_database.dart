import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class ConversationsTable extends Table {
  IntColumn get id => integer()();
  IntColumn get workspaceId => integer().withDefault(const Constant(0))();
  TextColumn get type => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get lastMessagePreview => text().withDefault(const Constant(''))();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MessagesTable extends Table {
  IntColumn get id => integer()();
  IntColumn get conversationId => integer()();
  IntColumn get senderId => integer()();
  TextColumn get senderName => text()();
  TextColumn get plaintextBody => text().withDefault(const Constant(''))();
  TextColumn get encryptedBody => text().withDefault(const Constant(''))();
  TextColumn get attachmentsJson => text().withDefault(const Constant('[]'))();
  TextColumn get messageType => text().withDefault(const Constant('text'))();
  IntColumn get attachmentCount => integer().withDefault(const Constant(0))();
  TextColumn get clientMessageId => text().withDefault(const Constant(''))();
  TextColumn get deliveryState => text().withDefault(const Constant('sent'))();
  TextColumn get failureReason => text().nullable()();
  BoolColumn get isPending => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class QueuedOutgoingMessagesTable extends Table {
  TextColumn get clientMessageId => text()();
  IntColumn get conversationId => integer()();
  IntColumn get senderId => integer()();
  TextColumn get senderName => text()();
  TextColumn get plaintext => text()();
  TextColumn get encryptedPayload => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  TextColumn get deliveryState =>
      text().withDefault(const Constant('pending'))();
  TextColumn get failureReason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {clientMessageId};
}

class ConversationSyncStateTable extends Table {
  IntColumn get conversationId => integer()();
  IntColumn get lastMessageId => integer().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {conversationId};
}

class VerifiedKeysTable extends Table {
  IntColumn get userId => integer()();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
  TextColumn get kind => text()();
  TextColumn get verifiedFingerprint => text().nullable()();
  TextColumn get lastSeenFingerprint => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {userId, deviceId, kind};
}

class DraftsTable extends Table {
  IntColumn get conversationId => integer()();
  TextColumn get draftText => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {conversationId};
}

@DriftDatabase(
  tables: [
    ConversationsTable,
    MessagesTable,
    QueuedOutgoingMessagesTable,
    ConversationSyncStateTable,
    VerifiedKeysTable,
    DraftsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.executor);

  static AppDatabase? _sharedInstance;

  factory AppDatabase() {
    return _sharedInstance ??= AppDatabase._(_openConnection());
  }

  factory AppDatabase.inMemory() {
    return AppDatabase._(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        final messageColumns = await _readColumnNames('messages_table');
        if (!messageColumns.contains('attachments_json')) {
          await migrator.addColumn(messagesTable, messagesTable.attachmentsJson);
        }
      }
      if (from < 3) {
        await _rebuildVerifiedKeysTableV3();
      }
    },
    beforeOpen: (details) async {
      await _ensureVerifiedKeysTableIsHealthy();
    },
  );

  Future<Set<String>> _readColumnNames(String tableName) async {
    final rows = await customSelect(
      "PRAGMA table_info('$tableName');",
    ).get();
    return rows
        .map((row) => row.data['name'])
        .whereType<String>()
        .toSet();
  }

  Future<void> _rebuildVerifiedKeysTableV3() async {
    final existingColumns = await _readColumnNames('verified_keys_table');
    final hasDeviceId = existingColumns.contains('device_id');
    final hasCreatedAt = existingColumns.contains('created_at');
    final hasUpdatedAt = existingColumns.contains('updated_at');

    await customStatement('''
      CREATE TABLE verified_keys_table_v3 (
        user_id INTEGER NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL,
        verified_fingerprint TEXT NULL,
        last_seen_fingerprint TEXT NULL,
        created_at INTEGER NOT NULL DEFAULT (CAST(unixepoch('now') * 1000 AS INTEGER)),
        updated_at INTEGER NOT NULL DEFAULT (CAST(unixepoch('now') * 1000 AS INTEGER)),
        PRIMARY KEY (user_id, device_id, kind)
      );
    ''');

    await customStatement('''
      INSERT OR REPLACE INTO verified_keys_table_v3 (
        user_id,
        device_id,
        kind,
        verified_fingerprint,
        last_seen_fingerprint,
        created_at,
        updated_at
      )
      SELECT
        user_id,
        ${hasDeviceId ? 'COALESCE(device_id, \'\')' : "''"},
        kind,
        verified_fingerprint,
        last_seen_fingerprint,
        ${hasCreatedAt ? _verifiedKeysDateConversionSql('created_at') : "(CAST(unixepoch('now') * 1000 AS INTEGER))"},
        ${hasUpdatedAt ? _verifiedKeysDateConversionSql('updated_at') : "(CAST(unixepoch('now') * 1000 AS INTEGER))"}
      FROM verified_keys_table;
    ''');

    await customStatement('DROP TABLE verified_keys_table;');
    await customStatement(
      'ALTER TABLE verified_keys_table_v3 RENAME TO verified_keys_table;',
    );
  }

  String _verifiedKeysDateConversionSql(String columnName) {
    return '''
      CASE
        WHEN typeof($columnName) = 'integer' THEN $columnName
        WHEN typeof($columnName) = 'text' THEN CAST(unixepoch($columnName) * 1000 AS INTEGER)
        ELSE CAST(unixepoch('now') * 1000 AS INTEGER)
      END
    ''';
  }

  Future<void> _ensureVerifiedKeysTableIsHealthy() async {
    final rows = await customSelect(
      "PRAGMA table_info('verified_keys_table');",
    ).get();
    if (rows.isEmpty) {
      return;
    }
    final names = rows.map((row) => row.data['name']).whereType<String>().toSet();
    final typesByName = {
      for (final row in rows)
        if (row.data['name'] is String)
          row.data['name'] as String:
              (row.data['type'] as String? ?? '').toUpperCase(),
    };
    final pkColumnCount = rows.where((row) => ((row.data['pk'] as int?) ?? 0) > 0).length;
    final isHealthy =
        names.contains('device_id') &&
        names.contains('created_at') &&
        names.contains('updated_at') &&
        pkColumnCount >= 3 &&
        typesByName['created_at'] == 'INTEGER' &&
        typesByName['updated_at'] == 'INTEGER';
    if (!isHealthy) {
      await _rebuildVerifiedKeysTableV3();
    }
  }

  Future<void> upsertConversation(ConversationsTableCompanion entry) async {
    await into(conversationsTable).insertOnConflictUpdate(entry);
  }

  Future<List<ConversationsTableData>> readConversations() {
    return (select(conversationsTable)..orderBy([
          (t) => OrderingTerm.desc(t.updatedAt),
          (t) => OrderingTerm.desc(t.id),
        ]))
        .get();
  }

  Future<List<ConversationsTableData>> readConversationsForWorkspace(
    int workspaceId,
  ) {
    return (select(conversationsTable)
          ..where((tbl) => tbl.workspaceId.equals(workspaceId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.updatedAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .get();
  }

  Future<void> upsertMessage(MessagesTableCompanion entry) async {
    await into(messagesTable).insertOnConflictUpdate(entry);
  }

  Future<List<MessagesTableData>> readMessagesForConversation(
    int conversationId,
  ) {
    return (select(messagesTable)
          ..where((tbl) => tbl.conversationId.equals(conversationId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  Future<void> upsertQueuedMessage(
    QueuedOutgoingMessagesTableCompanion entry,
  ) async {
    await into(queuedOutgoingMessagesTable).insertOnConflictUpdate(entry);
  }

  Future<List<QueuedOutgoingMessagesTableData>>
  readQueuedMessagesForConversation(int conversationId) {
    return (select(queuedOutgoingMessagesTable)
          ..where((tbl) => tbl.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<QueuedOutgoingMessagesTableData>> readAllQueuedMessages() {
    return (select(
      queuedOutgoingMessagesTable,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
  }

  Future<void> removeQueuedMessage(String clientMessageId) async {
    await (delete(
      queuedOutgoingMessagesTable,
    )..where((tbl) => tbl.clientMessageId.equals(clientMessageId))).go();
  }

  Future<void> clearQueuedMessages() async {
    await delete(queuedOutgoingMessagesTable).go();
  }

  Future<void> upsertSyncState(
    ConversationSyncStateTableCompanion entry,
  ) async {
    await into(conversationSyncStateTable).insertOnConflictUpdate(entry);
  }

  Future<ConversationSyncStateTableData?> readSyncState(int conversationId) {
    return (select(conversationSyncStateTable)
          ..where((tbl) => tbl.conversationId.equals(conversationId)))
        .getSingleOrNull();
  }

  Future<void> upsertVerifiedKey(VerifiedKeysTableCompanion entry) async {
    await into(verifiedKeysTable).insertOnConflictUpdate(entry);
  }

  Future<List<VerifiedKeysTableData>> readVerifiedKeysForUser(int userId) {
    return (select(
      verifiedKeysTable,
    )..where((tbl) => tbl.userId.equals(userId))).get();
  }

  Future<List<VerifiedKeysTableData>> readVerifiedKeysForDevice({
    required int userId,
    required String deviceId,
  }) {
    return (select(verifiedKeysTable)..where(
          (tbl) => tbl.userId.equals(userId) & tbl.deviceId.equals(deviceId),
        ))
        .get();
  }

  Future<void> upsertDraft(DraftsTableCompanion entry) async {
    await into(draftsTable).insertOnConflictUpdate(entry);
  }

  Future<DraftsTableData?> readDraft(int conversationId) {
    return (select(draftsTable)
          ..where((tbl) => tbl.conversationId.equals(conversationId)))
        .getSingleOrNull();
  }

  Future<void> clearAllChatData() async {
    await batch((batch) {
      batch.deleteAll(messagesTable);
      batch.deleteAll(conversationsTable);
      batch.deleteAll(queuedOutgoingMessagesTable);
      batch.deleteAll(conversationSyncStateTable);
      batch.deleteAll(draftsTable);
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'pqc_chat_app.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
