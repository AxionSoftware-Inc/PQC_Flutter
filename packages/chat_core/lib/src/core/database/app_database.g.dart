// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ConversationsTableTable extends ConversationsTable
    with TableInfo<$ConversationsTableTable, ConversationsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<int> workspaceId = GeneratedColumn<int>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _lastMessagePreviewMeta =
      const VerificationMeta('lastMessagePreview');
  @override
  late final GeneratedColumn<String> lastMessagePreview =
      GeneratedColumn<String>(
        'last_message_preview',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    type,
    title,
    lastMessagePreview,
    unreadCount,
    updatedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('last_message_preview')) {
      context.handle(
        _lastMessagePreviewMeta,
        lastMessagePreview.isAcceptableOrUnknown(
          data['last_message_preview']!,
          _lastMessagePreviewMeta,
        ),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}workspace_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      lastMessagePreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_preview'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ConversationsTableTable createAlias(String alias) {
    return $ConversationsTableTable(attachedDatabase, alias);
  }
}

class ConversationsTableData extends DataClass
    implements Insertable<ConversationsTableData> {
  final int id;
  final int workspaceId;
  final String type;
  final String title;
  final String lastMessagePreview;
  final int unreadCount;
  final DateTime updatedAt;
  final DateTime createdAt;
  const ConversationsTableData({
    required this.id,
    required this.workspaceId,
    required this.type,
    required this.title,
    required this.lastMessagePreview,
    required this.unreadCount,
    required this.updatedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['workspace_id'] = Variable<int>(workspaceId);
    map['type'] = Variable<String>(type);
    map['title'] = Variable<String>(title);
    map['last_message_preview'] = Variable<String>(lastMessagePreview);
    map['unread_count'] = Variable<int>(unreadCount);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ConversationsTableCompanion toCompanion(bool nullToAbsent) {
    return ConversationsTableCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      type: Value(type),
      title: Value(title),
      lastMessagePreview: Value(lastMessagePreview),
      unreadCount: Value(unreadCount),
      updatedAt: Value(updatedAt),
      createdAt: Value(createdAt),
    );
  }

  factory ConversationsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationsTableData(
      id: serializer.fromJson<int>(json['id']),
      workspaceId: serializer.fromJson<int>(json['workspaceId']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String>(json['title']),
      lastMessagePreview: serializer.fromJson<String>(
        json['lastMessagePreview'],
      ),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'workspaceId': serializer.toJson<int>(workspaceId),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String>(title),
      'lastMessagePreview': serializer.toJson<String>(lastMessagePreview),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ConversationsTableData copyWith({
    int? id,
    int? workspaceId,
    String? type,
    String? title,
    String? lastMessagePreview,
    int? unreadCount,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) => ConversationsTableData(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    type: type ?? this.type,
    title: title ?? this.title,
    lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
    unreadCount: unreadCount ?? this.unreadCount,
    updatedAt: updatedAt ?? this.updatedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  ConversationsTableData copyWithCompanion(ConversationsTableCompanion data) {
    return ConversationsTableData(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      lastMessagePreview: data.lastMessagePreview.present
          ? data.lastMessagePreview.value
          : this.lastMessagePreview,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsTableData(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    type,
    title,
    lastMessagePreview,
    unreadCount,
    updatedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationsTableData &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.type == this.type &&
          other.title == this.title &&
          other.lastMessagePreview == this.lastMessagePreview &&
          other.unreadCount == this.unreadCount &&
          other.updatedAt == this.updatedAt &&
          other.createdAt == this.createdAt);
}

class ConversationsTableCompanion
    extends UpdateCompanion<ConversationsTableData> {
  final Value<int> id;
  final Value<int> workspaceId;
  final Value<String> type;
  final Value<String> title;
  final Value<String> lastMessagePreview;
  final Value<int> unreadCount;
  final Value<DateTime> updatedAt;
  final Value<DateTime> createdAt;
  const ConversationsTableCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ConversationsTableCompanion.insert({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    required String type,
    this.title = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.unreadCount = const Value.absent(),
    required DateTime updatedAt,
    required DateTime createdAt,
  }) : type = Value(type),
       updatedAt = Value(updatedAt),
       createdAt = Value(createdAt);
  static Insertable<ConversationsTableData> custom({
    Expression<int>? id,
    Expression<int>? workspaceId,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? lastMessagePreview,
    Expression<int>? unreadCount,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (lastMessagePreview != null)
        'last_message_preview': lastMessagePreview,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ConversationsTableCompanion copyWith({
    Value<int>? id,
    Value<int>? workspaceId,
    Value<String>? type,
    Value<String>? title,
    Value<String>? lastMessagePreview,
    Value<int>? unreadCount,
    Value<DateTime>? updatedAt,
    Value<DateTime>? createdAt,
  }) {
    return ConversationsTableCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      type: type ?? this.type,
      title: title ?? this.title,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<int>(workspaceId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (lastMessagePreview.present) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsTableCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $MessagesTableTable extends MessagesTable
    with TableInfo<$MessagesTableTable, MessagesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<int> senderId = GeneratedColumn<int>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderNameMeta = const VerificationMeta(
    'senderName',
  );
  @override
  late final GeneratedColumn<String> senderName = GeneratedColumn<String>(
    'sender_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _plaintextBodyMeta = const VerificationMeta(
    'plaintextBody',
  );
  @override
  late final GeneratedColumn<String> plaintextBody = GeneratedColumn<String>(
    'plaintext_body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _encryptedBodyMeta = const VerificationMeta(
    'encryptedBody',
  );
  @override
  late final GeneratedColumn<String> encryptedBody = GeneratedColumn<String>(
    'encrypted_body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _messageTypeMeta = const VerificationMeta(
    'messageType',
  );
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
    'message_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  );
  static const VerificationMeta _attachmentCountMeta = const VerificationMeta(
    'attachmentCount',
  );
  @override
  late final GeneratedColumn<int> attachmentCount = GeneratedColumn<int>(
    'attachment_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _clientMessageIdMeta = const VerificationMeta(
    'clientMessageId',
  );
  @override
  late final GeneratedColumn<String> clientMessageId = GeneratedColumn<String>(
    'client_message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _deliveryStateMeta = const VerificationMeta(
    'deliveryState',
  );
  @override
  late final GeneratedColumn<String> deliveryState = GeneratedColumn<String>(
    'delivery_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('sent'),
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPendingMeta = const VerificationMeta(
    'isPending',
  );
  @override
  late final GeneratedColumn<bool> isPending = GeneratedColumn<bool>(
    'is_pending',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pending" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    senderId,
    senderName,
    plaintextBody,
    encryptedBody,
    attachmentsJson,
    messageType,
    attachmentCount,
    clientMessageId,
    deliveryState,
    failureReason,
    isPending,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessagesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('sender_name')) {
      context.handle(
        _senderNameMeta,
        senderName.isAcceptableOrUnknown(data['sender_name']!, _senderNameMeta),
      );
    } else if (isInserting) {
      context.missing(_senderNameMeta);
    }
    if (data.containsKey('plaintext_body')) {
      context.handle(
        _plaintextBodyMeta,
        plaintextBody.isAcceptableOrUnknown(
          data['plaintext_body']!,
          _plaintextBodyMeta,
        ),
      );
    }
    if (data.containsKey('encrypted_body')) {
      context.handle(
        _encryptedBodyMeta,
        encryptedBody.isAcceptableOrUnknown(
          data['encrypted_body']!,
          _encryptedBodyMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('message_type')) {
      context.handle(
        _messageTypeMeta,
        messageType.isAcceptableOrUnknown(
          data['message_type']!,
          _messageTypeMeta,
        ),
      );
    }
    if (data.containsKey('attachment_count')) {
      context.handle(
        _attachmentCountMeta,
        attachmentCount.isAcceptableOrUnknown(
          data['attachment_count']!,
          _attachmentCountMeta,
        ),
      );
    }
    if (data.containsKey('client_message_id')) {
      context.handle(
        _clientMessageIdMeta,
        clientMessageId.isAcceptableOrUnknown(
          data['client_message_id']!,
          _clientMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('delivery_state')) {
      context.handle(
        _deliveryStateMeta,
        deliveryState.isAcceptableOrUnknown(
          data['delivery_state']!,
          _deliveryStateMeta,
        ),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    if (data.containsKey('is_pending')) {
      context.handle(
        _isPendingMeta,
        isPending.isAcceptableOrUnknown(data['is_pending']!, _isPendingMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessagesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessagesTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sender_id'],
      )!,
      senderName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_name'],
      )!,
      plaintextBody: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plaintext_body'],
      )!,
      encryptedBody: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_body'],
      )!,
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      )!,
      messageType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_type'],
      )!,
      attachmentCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attachment_count'],
      )!,
      clientMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_message_id'],
      )!,
      deliveryState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_state'],
      )!,
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      isPending: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pending'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MessagesTableTable createAlias(String alias) {
    return $MessagesTableTable(attachedDatabase, alias);
  }
}

class MessagesTableData extends DataClass
    implements Insertable<MessagesTableData> {
  final int id;
  final int conversationId;
  final int senderId;
  final String senderName;
  final String plaintextBody;
  final String encryptedBody;
  final String attachmentsJson;
  final String messageType;
  final int attachmentCount;
  final String clientMessageId;
  final String deliveryState;
  final String? failureReason;
  final bool isPending;
  final DateTime createdAt;
  const MessagesTableData({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.plaintextBody,
    required this.encryptedBody,
    required this.attachmentsJson,
    required this.messageType,
    required this.attachmentCount,
    required this.clientMessageId,
    required this.deliveryState,
    this.failureReason,
    required this.isPending,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['conversation_id'] = Variable<int>(conversationId);
    map['sender_id'] = Variable<int>(senderId);
    map['sender_name'] = Variable<String>(senderName);
    map['plaintext_body'] = Variable<String>(plaintextBody);
    map['encrypted_body'] = Variable<String>(encryptedBody);
    map['attachments_json'] = Variable<String>(attachmentsJson);
    map['message_type'] = Variable<String>(messageType);
    map['attachment_count'] = Variable<int>(attachmentCount);
    map['client_message_id'] = Variable<String>(clientMessageId);
    map['delivery_state'] = Variable<String>(deliveryState);
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    map['is_pending'] = Variable<bool>(isPending);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessagesTableCompanion toCompanion(bool nullToAbsent) {
    return MessagesTableCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      senderId: Value(senderId),
      senderName: Value(senderName),
      plaintextBody: Value(plaintextBody),
      encryptedBody: Value(encryptedBody),
      attachmentsJson: Value(attachmentsJson),
      messageType: Value(messageType),
      attachmentCount: Value(attachmentCount),
      clientMessageId: Value(clientMessageId),
      deliveryState: Value(deliveryState),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      isPending: Value(isPending),
      createdAt: Value(createdAt),
    );
  }

  factory MessagesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessagesTableData(
      id: serializer.fromJson<int>(json['id']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      senderId: serializer.fromJson<int>(json['senderId']),
      senderName: serializer.fromJson<String>(json['senderName']),
      plaintextBody: serializer.fromJson<String>(json['plaintextBody']),
      encryptedBody: serializer.fromJson<String>(json['encryptedBody']),
      attachmentsJson: serializer.fromJson<String>(json['attachmentsJson']),
      messageType: serializer.fromJson<String>(json['messageType']),
      attachmentCount: serializer.fromJson<int>(json['attachmentCount']),
      clientMessageId: serializer.fromJson<String>(json['clientMessageId']),
      deliveryState: serializer.fromJson<String>(json['deliveryState']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      isPending: serializer.fromJson<bool>(json['isPending']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conversationId': serializer.toJson<int>(conversationId),
      'senderId': serializer.toJson<int>(senderId),
      'senderName': serializer.toJson<String>(senderName),
      'plaintextBody': serializer.toJson<String>(plaintextBody),
      'encryptedBody': serializer.toJson<String>(encryptedBody),
      'attachmentsJson': serializer.toJson<String>(attachmentsJson),
      'messageType': serializer.toJson<String>(messageType),
      'attachmentCount': serializer.toJson<int>(attachmentCount),
      'clientMessageId': serializer.toJson<String>(clientMessageId),
      'deliveryState': serializer.toJson<String>(deliveryState),
      'failureReason': serializer.toJson<String?>(failureReason),
      'isPending': serializer.toJson<bool>(isPending),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  MessagesTableData copyWith({
    int? id,
    int? conversationId,
    int? senderId,
    String? senderName,
    String? plaintextBody,
    String? encryptedBody,
    String? attachmentsJson,
    String? messageType,
    int? attachmentCount,
    String? clientMessageId,
    String? deliveryState,
    Value<String?> failureReason = const Value.absent(),
    bool? isPending,
    DateTime? createdAt,
  }) => MessagesTableData(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    senderId: senderId ?? this.senderId,
    senderName: senderName ?? this.senderName,
    plaintextBody: plaintextBody ?? this.plaintextBody,
    encryptedBody: encryptedBody ?? this.encryptedBody,
    attachmentsJson: attachmentsJson ?? this.attachmentsJson,
    messageType: messageType ?? this.messageType,
    attachmentCount: attachmentCount ?? this.attachmentCount,
    clientMessageId: clientMessageId ?? this.clientMessageId,
    deliveryState: deliveryState ?? this.deliveryState,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    isPending: isPending ?? this.isPending,
    createdAt: createdAt ?? this.createdAt,
  );
  MessagesTableData copyWithCompanion(MessagesTableCompanion data) {
    return MessagesTableData(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      senderName: data.senderName.present
          ? data.senderName.value
          : this.senderName,
      plaintextBody: data.plaintextBody.present
          ? data.plaintextBody.value
          : this.plaintextBody,
      encryptedBody: data.encryptedBody.present
          ? data.encryptedBody.value
          : this.encryptedBody,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      messageType: data.messageType.present
          ? data.messageType.value
          : this.messageType,
      attachmentCount: data.attachmentCount.present
          ? data.attachmentCount.value
          : this.attachmentCount,
      clientMessageId: data.clientMessageId.present
          ? data.clientMessageId.value
          : this.clientMessageId,
      deliveryState: data.deliveryState.present
          ? data.deliveryState.value
          : this.deliveryState,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      isPending: data.isPending.present ? data.isPending.value : this.isPending,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessagesTableData(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('senderName: $senderName, ')
          ..write('plaintextBody: $plaintextBody, ')
          ..write('encryptedBody: $encryptedBody, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('messageType: $messageType, ')
          ..write('attachmentCount: $attachmentCount, ')
          ..write('clientMessageId: $clientMessageId, ')
          ..write('deliveryState: $deliveryState, ')
          ..write('failureReason: $failureReason, ')
          ..write('isPending: $isPending, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    senderId,
    senderName,
    plaintextBody,
    encryptedBody,
    attachmentsJson,
    messageType,
    attachmentCount,
    clientMessageId,
    deliveryState,
    failureReason,
    isPending,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessagesTableData &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.senderId == this.senderId &&
          other.senderName == this.senderName &&
          other.plaintextBody == this.plaintextBody &&
          other.encryptedBody == this.encryptedBody &&
          other.attachmentsJson == this.attachmentsJson &&
          other.messageType == this.messageType &&
          other.attachmentCount == this.attachmentCount &&
          other.clientMessageId == this.clientMessageId &&
          other.deliveryState == this.deliveryState &&
          other.failureReason == this.failureReason &&
          other.isPending == this.isPending &&
          other.createdAt == this.createdAt);
}

class MessagesTableCompanion extends UpdateCompanion<MessagesTableData> {
  final Value<int> id;
  final Value<int> conversationId;
  final Value<int> senderId;
  final Value<String> senderName;
  final Value<String> plaintextBody;
  final Value<String> encryptedBody;
  final Value<String> attachmentsJson;
  final Value<String> messageType;
  final Value<int> attachmentCount;
  final Value<String> clientMessageId;
  final Value<String> deliveryState;
  final Value<String?> failureReason;
  final Value<bool> isPending;
  final Value<DateTime> createdAt;
  const MessagesTableCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.senderName = const Value.absent(),
    this.plaintextBody = const Value.absent(),
    this.encryptedBody = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.messageType = const Value.absent(),
    this.attachmentCount = const Value.absent(),
    this.clientMessageId = const Value.absent(),
    this.deliveryState = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.isPending = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MessagesTableCompanion.insert({
    this.id = const Value.absent(),
    required int conversationId,
    required int senderId,
    required String senderName,
    this.plaintextBody = const Value.absent(),
    this.encryptedBody = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.messageType = const Value.absent(),
    this.attachmentCount = const Value.absent(),
    this.clientMessageId = const Value.absent(),
    this.deliveryState = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.isPending = const Value.absent(),
    required DateTime createdAt,
  }) : conversationId = Value(conversationId),
       senderId = Value(senderId),
       senderName = Value(senderName),
       createdAt = Value(createdAt);
  static Insertable<MessagesTableData> custom({
    Expression<int>? id,
    Expression<int>? conversationId,
    Expression<int>? senderId,
    Expression<String>? senderName,
    Expression<String>? plaintextBody,
    Expression<String>? encryptedBody,
    Expression<String>? attachmentsJson,
    Expression<String>? messageType,
    Expression<int>? attachmentCount,
    Expression<String>? clientMessageId,
    Expression<String>? deliveryState,
    Expression<String>? failureReason,
    Expression<bool>? isPending,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (senderId != null) 'sender_id': senderId,
      if (senderName != null) 'sender_name': senderName,
      if (plaintextBody != null) 'plaintext_body': plaintextBody,
      if (encryptedBody != null) 'encrypted_body': encryptedBody,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (messageType != null) 'message_type': messageType,
      if (attachmentCount != null) 'attachment_count': attachmentCount,
      if (clientMessageId != null) 'client_message_id': clientMessageId,
      if (deliveryState != null) 'delivery_state': deliveryState,
      if (failureReason != null) 'failure_reason': failureReason,
      if (isPending != null) 'is_pending': isPending,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MessagesTableCompanion copyWith({
    Value<int>? id,
    Value<int>? conversationId,
    Value<int>? senderId,
    Value<String>? senderName,
    Value<String>? plaintextBody,
    Value<String>? encryptedBody,
    Value<String>? attachmentsJson,
    Value<String>? messageType,
    Value<int>? attachmentCount,
    Value<String>? clientMessageId,
    Value<String>? deliveryState,
    Value<String?>? failureReason,
    Value<bool>? isPending,
    Value<DateTime>? createdAt,
  }) {
    return MessagesTableCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      plaintextBody: plaintextBody ?? this.plaintextBody,
      encryptedBody: encryptedBody ?? this.encryptedBody,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      messageType: messageType ?? this.messageType,
      attachmentCount: attachmentCount ?? this.attachmentCount,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      deliveryState: deliveryState ?? this.deliveryState,
      failureReason: failureReason ?? this.failureReason,
      isPending: isPending ?? this.isPending,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<int>(senderId.value);
    }
    if (senderName.present) {
      map['sender_name'] = Variable<String>(senderName.value);
    }
    if (plaintextBody.present) {
      map['plaintext_body'] = Variable<String>(plaintextBody.value);
    }
    if (encryptedBody.present) {
      map['encrypted_body'] = Variable<String>(encryptedBody.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (attachmentCount.present) {
      map['attachment_count'] = Variable<int>(attachmentCount.value);
    }
    if (clientMessageId.present) {
      map['client_message_id'] = Variable<String>(clientMessageId.value);
    }
    if (deliveryState.present) {
      map['delivery_state'] = Variable<String>(deliveryState.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (isPending.present) {
      map['is_pending'] = Variable<bool>(isPending.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesTableCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('senderName: $senderName, ')
          ..write('plaintextBody: $plaintextBody, ')
          ..write('encryptedBody: $encryptedBody, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('messageType: $messageType, ')
          ..write('attachmentCount: $attachmentCount, ')
          ..write('clientMessageId: $clientMessageId, ')
          ..write('deliveryState: $deliveryState, ')
          ..write('failureReason: $failureReason, ')
          ..write('isPending: $isPending, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $QueuedOutgoingMessagesTableTable extends QueuedOutgoingMessagesTable
    with
        TableInfo<
          $QueuedOutgoingMessagesTableTable,
          QueuedOutgoingMessagesTableData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueuedOutgoingMessagesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientMessageIdMeta = const VerificationMeta(
    'clientMessageId',
  );
  @override
  late final GeneratedColumn<String> clientMessageId = GeneratedColumn<String>(
    'client_message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<int> senderId = GeneratedColumn<int>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderNameMeta = const VerificationMeta(
    'senderName',
  );
  @override
  late final GeneratedColumn<String> senderName = GeneratedColumn<String>(
    'sender_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _plaintextMeta = const VerificationMeta(
    'plaintext',
  );
  @override
  late final GeneratedColumn<String> plaintext = GeneratedColumn<String>(
    'plaintext',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptedPayloadMeta = const VerificationMeta(
    'encryptedPayload',
  );
  @override
  late final GeneratedColumn<String> encryptedPayload = GeneratedColumn<String>(
    'encrypted_payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _messageTypeMeta = const VerificationMeta(
    'messageType',
  );
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
    'message_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextRetryAtMeta = const VerificationMeta(
    'nextRetryAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
    'next_retry_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveryStateMeta = const VerificationMeta(
    'deliveryState',
  );
  @override
  late final GeneratedColumn<String> deliveryState = GeneratedColumn<String>(
    'delivery_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    clientMessageId,
    conversationId,
    senderId,
    senderName,
    plaintext,
    encryptedPayload,
    messageType,
    attachmentsJson,
    createdAt,
    retryCount,
    nextRetryAt,
    deliveryState,
    failureReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queued_outgoing_messages_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueuedOutgoingMessagesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_message_id')) {
      context.handle(
        _clientMessageIdMeta,
        clientMessageId.isAcceptableOrUnknown(
          data['client_message_id']!,
          _clientMessageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientMessageIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('sender_name')) {
      context.handle(
        _senderNameMeta,
        senderName.isAcceptableOrUnknown(data['sender_name']!, _senderNameMeta),
      );
    } else if (isInserting) {
      context.missing(_senderNameMeta);
    }
    if (data.containsKey('plaintext')) {
      context.handle(
        _plaintextMeta,
        plaintext.isAcceptableOrUnknown(data['plaintext']!, _plaintextMeta),
      );
    } else if (isInserting) {
      context.missing(_plaintextMeta);
    }
    if (data.containsKey('encrypted_payload')) {
      context.handle(
        _encryptedPayloadMeta,
        encryptedPayload.isAcceptableOrUnknown(
          data['encrypted_payload']!,
          _encryptedPayloadMeta,
        ),
      );
    }
    if (data.containsKey('message_type')) {
      context.handle(
        _messageTypeMeta,
        messageType.isAcceptableOrUnknown(
          data['message_type']!,
          _messageTypeMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
        _nextRetryAtMeta,
        nextRetryAt.isAcceptableOrUnknown(
          data['next_retry_at']!,
          _nextRetryAtMeta,
        ),
      );
    }
    if (data.containsKey('delivery_state')) {
      context.handle(
        _deliveryStateMeta,
        deliveryState.isAcceptableOrUnknown(
          data['delivery_state']!,
          _deliveryStateMeta,
        ),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientMessageId};
  @override
  QueuedOutgoingMessagesTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueuedOutgoingMessagesTableData(
      clientMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_message_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sender_id'],
      )!,
      senderName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_name'],
      )!,
      plaintext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plaintext'],
      )!,
      encryptedPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_payload'],
      )!,
      messageType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_type'],
      )!,
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      nextRetryAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_retry_at'],
      ),
      deliveryState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_state'],
      )!,
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
    );
  }

  @override
  $QueuedOutgoingMessagesTableTable createAlias(String alias) {
    return $QueuedOutgoingMessagesTableTable(attachedDatabase, alias);
  }
}

class QueuedOutgoingMessagesTableData extends DataClass
    implements Insertable<QueuedOutgoingMessagesTableData> {
  final String clientMessageId;
  final int conversationId;
  final int senderId;
  final String senderName;
  final String plaintext;
  final String encryptedPayload;
  final String messageType;
  final String attachmentsJson;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? nextRetryAt;
  final String deliveryState;
  final String? failureReason;
  const QueuedOutgoingMessagesTableData({
    required this.clientMessageId,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.plaintext,
    required this.encryptedPayload,
    required this.messageType,
    required this.attachmentsJson,
    required this.createdAt,
    required this.retryCount,
    this.nextRetryAt,
    required this.deliveryState,
    this.failureReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_message_id'] = Variable<String>(clientMessageId);
    map['conversation_id'] = Variable<int>(conversationId);
    map['sender_id'] = Variable<int>(senderId);
    map['sender_name'] = Variable<String>(senderName);
    map['plaintext'] = Variable<String>(plaintext);
    map['encrypted_payload'] = Variable<String>(encryptedPayload);
    map['message_type'] = Variable<String>(messageType);
    map['attachments_json'] = Variable<String>(attachmentsJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    map['delivery_state'] = Variable<String>(deliveryState);
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    return map;
  }

  QueuedOutgoingMessagesTableCompanion toCompanion(bool nullToAbsent) {
    return QueuedOutgoingMessagesTableCompanion(
      clientMessageId: Value(clientMessageId),
      conversationId: Value(conversationId),
      senderId: Value(senderId),
      senderName: Value(senderName),
      plaintext: Value(plaintext),
      encryptedPayload: Value(encryptedPayload),
      messageType: Value(messageType),
      attachmentsJson: Value(attachmentsJson),
      createdAt: Value(createdAt),
      retryCount: Value(retryCount),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
      deliveryState: Value(deliveryState),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
    );
  }

  factory QueuedOutgoingMessagesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueuedOutgoingMessagesTableData(
      clientMessageId: serializer.fromJson<String>(json['clientMessageId']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      senderId: serializer.fromJson<int>(json['senderId']),
      senderName: serializer.fromJson<String>(json['senderName']),
      plaintext: serializer.fromJson<String>(json['plaintext']),
      encryptedPayload: serializer.fromJson<String>(json['encryptedPayload']),
      messageType: serializer.fromJson<String>(json['messageType']),
      attachmentsJson: serializer.fromJson<String>(json['attachmentsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
      deliveryState: serializer.fromJson<String>(json['deliveryState']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientMessageId': serializer.toJson<String>(clientMessageId),
      'conversationId': serializer.toJson<int>(conversationId),
      'senderId': serializer.toJson<int>(senderId),
      'senderName': serializer.toJson<String>(senderName),
      'plaintext': serializer.toJson<String>(plaintext),
      'encryptedPayload': serializer.toJson<String>(encryptedPayload),
      'messageType': serializer.toJson<String>(messageType),
      'attachmentsJson': serializer.toJson<String>(attachmentsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'retryCount': serializer.toJson<int>(retryCount),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
      'deliveryState': serializer.toJson<String>(deliveryState),
      'failureReason': serializer.toJson<String?>(failureReason),
    };
  }

  QueuedOutgoingMessagesTableData copyWith({
    String? clientMessageId,
    int? conversationId,
    int? senderId,
    String? senderName,
    String? plaintext,
    String? encryptedPayload,
    String? messageType,
    String? attachmentsJson,
    DateTime? createdAt,
    int? retryCount,
    Value<DateTime?> nextRetryAt = const Value.absent(),
    String? deliveryState,
    Value<String?> failureReason = const Value.absent(),
  }) => QueuedOutgoingMessagesTableData(
    clientMessageId: clientMessageId ?? this.clientMessageId,
    conversationId: conversationId ?? this.conversationId,
    senderId: senderId ?? this.senderId,
    senderName: senderName ?? this.senderName,
    plaintext: plaintext ?? this.plaintext,
    encryptedPayload: encryptedPayload ?? this.encryptedPayload,
    messageType: messageType ?? this.messageType,
    attachmentsJson: attachmentsJson ?? this.attachmentsJson,
    createdAt: createdAt ?? this.createdAt,
    retryCount: retryCount ?? this.retryCount,
    nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
    deliveryState: deliveryState ?? this.deliveryState,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
  );
  QueuedOutgoingMessagesTableData copyWithCompanion(
    QueuedOutgoingMessagesTableCompanion data,
  ) {
    return QueuedOutgoingMessagesTableData(
      clientMessageId: data.clientMessageId.present
          ? data.clientMessageId.value
          : this.clientMessageId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      senderName: data.senderName.present
          ? data.senderName.value
          : this.senderName,
      plaintext: data.plaintext.present ? data.plaintext.value : this.plaintext,
      encryptedPayload: data.encryptedPayload.present
          ? data.encryptedPayload.value
          : this.encryptedPayload,
      messageType: data.messageType.present
          ? data.messageType.value
          : this.messageType,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      nextRetryAt: data.nextRetryAt.present
          ? data.nextRetryAt.value
          : this.nextRetryAt,
      deliveryState: data.deliveryState.present
          ? data.deliveryState.value
          : this.deliveryState,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueuedOutgoingMessagesTableData(')
          ..write('clientMessageId: $clientMessageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('senderName: $senderName, ')
          ..write('plaintext: $plaintext, ')
          ..write('encryptedPayload: $encryptedPayload, ')
          ..write('messageType: $messageType, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('deliveryState: $deliveryState, ')
          ..write('failureReason: $failureReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    clientMessageId,
    conversationId,
    senderId,
    senderName,
    plaintext,
    encryptedPayload,
    messageType,
    attachmentsJson,
    createdAt,
    retryCount,
    nextRetryAt,
    deliveryState,
    failureReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueuedOutgoingMessagesTableData &&
          other.clientMessageId == this.clientMessageId &&
          other.conversationId == this.conversationId &&
          other.senderId == this.senderId &&
          other.senderName == this.senderName &&
          other.plaintext == this.plaintext &&
          other.encryptedPayload == this.encryptedPayload &&
          other.messageType == this.messageType &&
          other.attachmentsJson == this.attachmentsJson &&
          other.createdAt == this.createdAt &&
          other.retryCount == this.retryCount &&
          other.nextRetryAt == this.nextRetryAt &&
          other.deliveryState == this.deliveryState &&
          other.failureReason == this.failureReason);
}

class QueuedOutgoingMessagesTableCompanion
    extends UpdateCompanion<QueuedOutgoingMessagesTableData> {
  final Value<String> clientMessageId;
  final Value<int> conversationId;
  final Value<int> senderId;
  final Value<String> senderName;
  final Value<String> plaintext;
  final Value<String> encryptedPayload;
  final Value<String> messageType;
  final Value<String> attachmentsJson;
  final Value<DateTime> createdAt;
  final Value<int> retryCount;
  final Value<DateTime?> nextRetryAt;
  final Value<String> deliveryState;
  final Value<String?> failureReason;
  final Value<int> rowid;
  const QueuedOutgoingMessagesTableCompanion({
    this.clientMessageId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.senderName = const Value.absent(),
    this.plaintext = const Value.absent(),
    this.encryptedPayload = const Value.absent(),
    this.messageType = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.deliveryState = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QueuedOutgoingMessagesTableCompanion.insert({
    required String clientMessageId,
    required int conversationId,
    required int senderId,
    required String senderName,
    required String plaintext,
    this.encryptedPayload = const Value.absent(),
    this.messageType = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    required DateTime createdAt,
    this.retryCount = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.deliveryState = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : clientMessageId = Value(clientMessageId),
       conversationId = Value(conversationId),
       senderId = Value(senderId),
       senderName = Value(senderName),
       plaintext = Value(plaintext),
       createdAt = Value(createdAt);
  static Insertable<QueuedOutgoingMessagesTableData> custom({
    Expression<String>? clientMessageId,
    Expression<int>? conversationId,
    Expression<int>? senderId,
    Expression<String>? senderName,
    Expression<String>? plaintext,
    Expression<String>? encryptedPayload,
    Expression<String>? messageType,
    Expression<String>? attachmentsJson,
    Expression<DateTime>? createdAt,
    Expression<int>? retryCount,
    Expression<DateTime>? nextRetryAt,
    Expression<String>? deliveryState,
    Expression<String>? failureReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientMessageId != null) 'client_message_id': clientMessageId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (senderId != null) 'sender_id': senderId,
      if (senderName != null) 'sender_name': senderName,
      if (plaintext != null) 'plaintext': plaintext,
      if (encryptedPayload != null) 'encrypted_payload': encryptedPayload,
      if (messageType != null) 'message_type': messageType,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (retryCount != null) 'retry_count': retryCount,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (deliveryState != null) 'delivery_state': deliveryState,
      if (failureReason != null) 'failure_reason': failureReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QueuedOutgoingMessagesTableCompanion copyWith({
    Value<String>? clientMessageId,
    Value<int>? conversationId,
    Value<int>? senderId,
    Value<String>? senderName,
    Value<String>? plaintext,
    Value<String>? encryptedPayload,
    Value<String>? messageType,
    Value<String>? attachmentsJson,
    Value<DateTime>? createdAt,
    Value<int>? retryCount,
    Value<DateTime?>? nextRetryAt,
    Value<String>? deliveryState,
    Value<String?>? failureReason,
    Value<int>? rowid,
  }) {
    return QueuedOutgoingMessagesTableCompanion(
      clientMessageId: clientMessageId ?? this.clientMessageId,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      plaintext: plaintext ?? this.plaintext,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      messageType: messageType ?? this.messageType,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      deliveryState: deliveryState ?? this.deliveryState,
      failureReason: failureReason ?? this.failureReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientMessageId.present) {
      map['client_message_id'] = Variable<String>(clientMessageId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<int>(senderId.value);
    }
    if (senderName.present) {
      map['sender_name'] = Variable<String>(senderName.value);
    }
    if (plaintext.present) {
      map['plaintext'] = Variable<String>(plaintext.value);
    }
    if (encryptedPayload.present) {
      map['encrypted_payload'] = Variable<String>(encryptedPayload.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    if (deliveryState.present) {
      map['delivery_state'] = Variable<String>(deliveryState.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueuedOutgoingMessagesTableCompanion(')
          ..write('clientMessageId: $clientMessageId, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('senderName: $senderName, ')
          ..write('plaintext: $plaintext, ')
          ..write('encryptedPayload: $encryptedPayload, ')
          ..write('messageType: $messageType, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('deliveryState: $deliveryState, ')
          ..write('failureReason: $failureReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationSyncStateTableTable extends ConversationSyncStateTable
    with
        TableInfo<
          $ConversationSyncStateTableTable,
          ConversationSyncStateTableData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationSyncStateTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageIdMeta = const VerificationMeta(
    'lastMessageId',
  );
  @override
  late final GeneratedColumn<int> lastMessageId = GeneratedColumn<int>(
    'last_message_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    conversationId,
    lastMessageId,
    lastSyncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversation_sync_state_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationSyncStateTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    }
    if (data.containsKey('last_message_id')) {
      context.handle(
        _lastMessageIdMeta,
        lastMessageId.isAcceptableOrUnknown(
          data['last_message_id']!,
          _lastMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId};
  @override
  ConversationSyncStateTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationSyncStateTableData(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      lastMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_message_id'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      ),
    );
  }

  @override
  $ConversationSyncStateTableTable createAlias(String alias) {
    return $ConversationSyncStateTableTable(attachedDatabase, alias);
  }
}

class ConversationSyncStateTableData extends DataClass
    implements Insertable<ConversationSyncStateTableData> {
  final int conversationId;
  final int? lastMessageId;
  final DateTime? lastSyncedAt;
  const ConversationSyncStateTableData({
    required this.conversationId,
    this.lastMessageId,
    this.lastSyncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<int>(conversationId);
    if (!nullToAbsent || lastMessageId != null) {
      map['last_message_id'] = Variable<int>(lastMessageId);
    }
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    }
    return map;
  }

  ConversationSyncStateTableCompanion toCompanion(bool nullToAbsent) {
    return ConversationSyncStateTableCompanion(
      conversationId: Value(conversationId),
      lastMessageId: lastMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageId),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
    );
  }

  factory ConversationSyncStateTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationSyncStateTableData(
      conversationId: serializer.fromJson<int>(json['conversationId']),
      lastMessageId: serializer.fromJson<int?>(json['lastMessageId']),
      lastSyncedAt: serializer.fromJson<DateTime?>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<int>(conversationId),
      'lastMessageId': serializer.toJson<int?>(lastMessageId),
      'lastSyncedAt': serializer.toJson<DateTime?>(lastSyncedAt),
    };
  }

  ConversationSyncStateTableData copyWith({
    int? conversationId,
    Value<int?> lastMessageId = const Value.absent(),
    Value<DateTime?> lastSyncedAt = const Value.absent(),
  }) => ConversationSyncStateTableData(
    conversationId: conversationId ?? this.conversationId,
    lastMessageId: lastMessageId.present
        ? lastMessageId.value
        : this.lastMessageId,
    lastSyncedAt: lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
  );
  ConversationSyncStateTableData copyWithCompanion(
    ConversationSyncStateTableCompanion data,
  ) {
    return ConversationSyncStateTableData(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      lastMessageId: data.lastMessageId.present
          ? data.lastMessageId.value
          : this.lastMessageId,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationSyncStateTableData(')
          ..write('conversationId: $conversationId, ')
          ..write('lastMessageId: $lastMessageId, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(conversationId, lastMessageId, lastSyncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationSyncStateTableData &&
          other.conversationId == this.conversationId &&
          other.lastMessageId == this.lastMessageId &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class ConversationSyncStateTableCompanion
    extends UpdateCompanion<ConversationSyncStateTableData> {
  final Value<int> conversationId;
  final Value<int?> lastMessageId;
  final Value<DateTime?> lastSyncedAt;
  const ConversationSyncStateTableCompanion({
    this.conversationId = const Value.absent(),
    this.lastMessageId = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
  });
  ConversationSyncStateTableCompanion.insert({
    this.conversationId = const Value.absent(),
    this.lastMessageId = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
  });
  static Insertable<ConversationSyncStateTableData> custom({
    Expression<int>? conversationId,
    Expression<int>? lastMessageId,
    Expression<DateTime>? lastSyncedAt,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (lastMessageId != null) 'last_message_id': lastMessageId,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
    });
  }

  ConversationSyncStateTableCompanion copyWith({
    Value<int>? conversationId,
    Value<int?>? lastMessageId,
    Value<DateTime?>? lastSyncedAt,
  }) {
    return ConversationSyncStateTableCompanion(
      conversationId: conversationId ?? this.conversationId,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (lastMessageId.present) {
      map['last_message_id'] = Variable<int>(lastMessageId.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationSyncStateTableCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('lastMessageId: $lastMessageId, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }
}

class $VerifiedKeysTableTable extends VerifiedKeysTable
    with TableInfo<$VerifiedKeysTableTable, VerifiedKeysTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VerifiedKeysTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<int> userId = GeneratedColumn<int>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verifiedFingerprintMeta =
      const VerificationMeta('verifiedFingerprint');
  @override
  late final GeneratedColumn<String> verifiedFingerprint =
      GeneratedColumn<String>(
        'verified_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastSeenFingerprintMeta =
      const VerificationMeta('lastSeenFingerprint');
  @override
  late final GeneratedColumn<String> lastSeenFingerprint =
      GeneratedColumn<String>(
        'last_seen_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    deviceId,
    kind,
    verifiedFingerprint,
    lastSeenFingerprint,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'verified_keys_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<VerifiedKeysTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('verified_fingerprint')) {
      context.handle(
        _verifiedFingerprintMeta,
        verifiedFingerprint.isAcceptableOrUnknown(
          data['verified_fingerprint']!,
          _verifiedFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('last_seen_fingerprint')) {
      context.handle(
        _lastSeenFingerprintMeta,
        lastSeenFingerprint.isAcceptableOrUnknown(
          data['last_seen_fingerprint']!,
          _lastSeenFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, deviceId, kind};
  @override
  VerifiedKeysTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VerifiedKeysTableData(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      verifiedFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verified_fingerprint'],
      ),
      lastSeenFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_seen_fingerprint'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $VerifiedKeysTableTable createAlias(String alias) {
    return $VerifiedKeysTableTable(attachedDatabase, alias);
  }
}

class VerifiedKeysTableData extends DataClass
    implements Insertable<VerifiedKeysTableData> {
  final int userId;
  final String deviceId;
  final String kind;
  final String? verifiedFingerprint;
  final String? lastSeenFingerprint;
  final DateTime createdAt;
  final DateTime updatedAt;
  const VerifiedKeysTableData({
    required this.userId,
    required this.deviceId,
    required this.kind,
    this.verifiedFingerprint,
    this.lastSeenFingerprint,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<int>(userId);
    map['device_id'] = Variable<String>(deviceId);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || verifiedFingerprint != null) {
      map['verified_fingerprint'] = Variable<String>(verifiedFingerprint);
    }
    if (!nullToAbsent || lastSeenFingerprint != null) {
      map['last_seen_fingerprint'] = Variable<String>(lastSeenFingerprint);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  VerifiedKeysTableCompanion toCompanion(bool nullToAbsent) {
    return VerifiedKeysTableCompanion(
      userId: Value(userId),
      deviceId: Value(deviceId),
      kind: Value(kind),
      verifiedFingerprint: verifiedFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedFingerprint),
      lastSeenFingerprint: lastSeenFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenFingerprint),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory VerifiedKeysTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VerifiedKeysTableData(
      userId: serializer.fromJson<int>(json['userId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      kind: serializer.fromJson<String>(json['kind']),
      verifiedFingerprint: serializer.fromJson<String?>(
        json['verifiedFingerprint'],
      ),
      lastSeenFingerprint: serializer.fromJson<String?>(
        json['lastSeenFingerprint'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<int>(userId),
      'deviceId': serializer.toJson<String>(deviceId),
      'kind': serializer.toJson<String>(kind),
      'verifiedFingerprint': serializer.toJson<String?>(verifiedFingerprint),
      'lastSeenFingerprint': serializer.toJson<String?>(lastSeenFingerprint),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  VerifiedKeysTableData copyWith({
    int? userId,
    String? deviceId,
    String? kind,
    Value<String?> verifiedFingerprint = const Value.absent(),
    Value<String?> lastSeenFingerprint = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => VerifiedKeysTableData(
    userId: userId ?? this.userId,
    deviceId: deviceId ?? this.deviceId,
    kind: kind ?? this.kind,
    verifiedFingerprint: verifiedFingerprint.present
        ? verifiedFingerprint.value
        : this.verifiedFingerprint,
    lastSeenFingerprint: lastSeenFingerprint.present
        ? lastSeenFingerprint.value
        : this.lastSeenFingerprint,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  VerifiedKeysTableData copyWithCompanion(VerifiedKeysTableCompanion data) {
    return VerifiedKeysTableData(
      userId: data.userId.present ? data.userId.value : this.userId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      kind: data.kind.present ? data.kind.value : this.kind,
      verifiedFingerprint: data.verifiedFingerprint.present
          ? data.verifiedFingerprint.value
          : this.verifiedFingerprint,
      lastSeenFingerprint: data.lastSeenFingerprint.present
          ? data.lastSeenFingerprint.value
          : this.lastSeenFingerprint,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VerifiedKeysTableData(')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('kind: $kind, ')
          ..write('verifiedFingerprint: $verifiedFingerprint, ')
          ..write('lastSeenFingerprint: $lastSeenFingerprint, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    deviceId,
    kind,
    verifiedFingerprint,
    lastSeenFingerprint,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VerifiedKeysTableData &&
          other.userId == this.userId &&
          other.deviceId == this.deviceId &&
          other.kind == this.kind &&
          other.verifiedFingerprint == this.verifiedFingerprint &&
          other.lastSeenFingerprint == this.lastSeenFingerprint &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class VerifiedKeysTableCompanion
    extends UpdateCompanion<VerifiedKeysTableData> {
  final Value<int> userId;
  final Value<String> deviceId;
  final Value<String> kind;
  final Value<String?> verifiedFingerprint;
  final Value<String?> lastSeenFingerprint;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const VerifiedKeysTableCompanion({
    this.userId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.kind = const Value.absent(),
    this.verifiedFingerprint = const Value.absent(),
    this.lastSeenFingerprint = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VerifiedKeysTableCompanion.insert({
    required int userId,
    this.deviceId = const Value.absent(),
    required String kind,
    this.verifiedFingerprint = const Value.absent(),
    this.lastSeenFingerprint = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       kind = Value(kind);
  static Insertable<VerifiedKeysTableData> custom({
    Expression<int>? userId,
    Expression<String>? deviceId,
    Expression<String>? kind,
    Expression<String>? verifiedFingerprint,
    Expression<String>? lastSeenFingerprint,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (deviceId != null) 'device_id': deviceId,
      if (kind != null) 'kind': kind,
      if (verifiedFingerprint != null)
        'verified_fingerprint': verifiedFingerprint,
      if (lastSeenFingerprint != null)
        'last_seen_fingerprint': lastSeenFingerprint,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VerifiedKeysTableCompanion copyWith({
    Value<int>? userId,
    Value<String>? deviceId,
    Value<String>? kind,
    Value<String?>? verifiedFingerprint,
    Value<String?>? lastSeenFingerprint,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return VerifiedKeysTableCompanion(
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      kind: kind ?? this.kind,
      verifiedFingerprint: verifiedFingerprint ?? this.verifiedFingerprint,
      lastSeenFingerprint: lastSeenFingerprint ?? this.lastSeenFingerprint,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<int>(userId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (verifiedFingerprint.present) {
      map['verified_fingerprint'] = Variable<String>(verifiedFingerprint.value);
    }
    if (lastSeenFingerprint.present) {
      map['last_seen_fingerprint'] = Variable<String>(
        lastSeenFingerprint.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VerifiedKeysTableCompanion(')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('kind: $kind, ')
          ..write('verifiedFingerprint: $verifiedFingerprint, ')
          ..write('lastSeenFingerprint: $lastSeenFingerprint, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DraftsTableTable extends DraftsTable
    with TableInfo<$DraftsTableTable, DraftsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DraftsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _draftTextMeta = const VerificationMeta(
    'draftText',
  );
  @override
  late final GeneratedColumn<String> draftText = GeneratedColumn<String>(
    'draft_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [conversationId, draftText, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drafts_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<DraftsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    }
    if (data.containsKey('draft_text')) {
      context.handle(
        _draftTextMeta,
        draftText.isAcceptableOrUnknown(data['draft_text']!, _draftTextMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId};
  @override
  DraftsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DraftsTableData(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      draftText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_text'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DraftsTableTable createAlias(String alias) {
    return $DraftsTableTable(attachedDatabase, alias);
  }
}

class DraftsTableData extends DataClass implements Insertable<DraftsTableData> {
  final int conversationId;
  final String draftText;
  final DateTime updatedAt;
  const DraftsTableData({
    required this.conversationId,
    required this.draftText,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<int>(conversationId);
    map['draft_text'] = Variable<String>(draftText);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DraftsTableCompanion toCompanion(bool nullToAbsent) {
    return DraftsTableCompanion(
      conversationId: Value(conversationId),
      draftText: Value(draftText),
      updatedAt: Value(updatedAt),
    );
  }

  factory DraftsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DraftsTableData(
      conversationId: serializer.fromJson<int>(json['conversationId']),
      draftText: serializer.fromJson<String>(json['draftText']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<int>(conversationId),
      'draftText': serializer.toJson<String>(draftText),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DraftsTableData copyWith({
    int? conversationId,
    String? draftText,
    DateTime? updatedAt,
  }) => DraftsTableData(
    conversationId: conversationId ?? this.conversationId,
    draftText: draftText ?? this.draftText,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DraftsTableData copyWithCompanion(DraftsTableCompanion data) {
    return DraftsTableData(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      draftText: data.draftText.present ? data.draftText.value : this.draftText,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DraftsTableData(')
          ..write('conversationId: $conversationId, ')
          ..write('draftText: $draftText, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(conversationId, draftText, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DraftsTableData &&
          other.conversationId == this.conversationId &&
          other.draftText == this.draftText &&
          other.updatedAt == this.updatedAt);
}

class DraftsTableCompanion extends UpdateCompanion<DraftsTableData> {
  final Value<int> conversationId;
  final Value<String> draftText;
  final Value<DateTime> updatedAt;
  const DraftsTableCompanion({
    this.conversationId = const Value.absent(),
    this.draftText = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DraftsTableCompanion.insert({
    this.conversationId = const Value.absent(),
    this.draftText = const Value.absent(),
    required DateTime updatedAt,
  }) : updatedAt = Value(updatedAt);
  static Insertable<DraftsTableData> custom({
    Expression<int>? conversationId,
    Expression<String>? draftText,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (draftText != null) 'draft_text': draftText,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DraftsTableCompanion copyWith({
    Value<int>? conversationId,
    Value<String>? draftText,
    Value<DateTime>? updatedAt,
  }) {
    return DraftsTableCompanion(
      conversationId: conversationId ?? this.conversationId,
      draftText: draftText ?? this.draftText,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (draftText.present) {
      map['draft_text'] = Variable<String>(draftText.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DraftsTableCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('draftText: $draftText, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConversationsTableTable conversationsTable =
      $ConversationsTableTable(this);
  late final $MessagesTableTable messagesTable = $MessagesTableTable(this);
  late final $QueuedOutgoingMessagesTableTable queuedOutgoingMessagesTable =
      $QueuedOutgoingMessagesTableTable(this);
  late final $ConversationSyncStateTableTable conversationSyncStateTable =
      $ConversationSyncStateTableTable(this);
  late final $VerifiedKeysTableTable verifiedKeysTable =
      $VerifiedKeysTableTable(this);
  late final $DraftsTableTable draftsTable = $DraftsTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    conversationsTable,
    messagesTable,
    queuedOutgoingMessagesTable,
    conversationSyncStateTable,
    verifiedKeysTable,
    draftsTable,
  ];
}

typedef $$ConversationsTableTableCreateCompanionBuilder =
    ConversationsTableCompanion Function({
      Value<int> id,
      Value<int> workspaceId,
      required String type,
      Value<String> title,
      Value<String> lastMessagePreview,
      Value<int> unreadCount,
      required DateTime updatedAt,
      required DateTime createdAt,
    });
typedef $$ConversationsTableTableUpdateCompanionBuilder =
    ConversationsTableCompanion Function({
      Value<int> id,
      Value<int> workspaceId,
      Value<String> type,
      Value<String> title,
      Value<String> lastMessagePreview,
      Value<int> unreadCount,
      Value<DateTime> updatedAt,
      Value<DateTime> createdAt,
    });

class $$ConversationsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ConversationsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationsTableTable,
          ConversationsTableData,
          $$ConversationsTableTableFilterComposer,
          $$ConversationsTableTableOrderingComposer,
          $$ConversationsTableTableAnnotationComposer,
          $$ConversationsTableTableCreateCompanionBuilder,
          $$ConversationsTableTableUpdateCompanionBuilder,
          (
            ConversationsTableData,
            BaseReferences<
              _$AppDatabase,
              $ConversationsTableTable,
              ConversationsTableData
            >,
          ),
          ConversationsTableData,
          PrefetchHooks Function()
        > {
  $$ConversationsTableTableTableManager(
    _$AppDatabase db,
    $ConversationsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> workspaceId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> lastMessagePreview = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ConversationsTableCompanion(
                id: id,
                workspaceId: workspaceId,
                type: type,
                title: title,
                lastMessagePreview: lastMessagePreview,
                unreadCount: unreadCount,
                updatedAt: updatedAt,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> workspaceId = const Value.absent(),
                required String type,
                Value<String> title = const Value.absent(),
                Value<String> lastMessagePreview = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                required DateTime updatedAt,
                required DateTime createdAt,
              }) => ConversationsTableCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                type: type,
                title: title,
                lastMessagePreview: lastMessagePreview,
                unreadCount: unreadCount,
                updatedAt: updatedAt,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationsTableTable,
      ConversationsTableData,
      $$ConversationsTableTableFilterComposer,
      $$ConversationsTableTableOrderingComposer,
      $$ConversationsTableTableAnnotationComposer,
      $$ConversationsTableTableCreateCompanionBuilder,
      $$ConversationsTableTableUpdateCompanionBuilder,
      (
        ConversationsTableData,
        BaseReferences<
          _$AppDatabase,
          $ConversationsTableTable,
          ConversationsTableData
        >,
      ),
      ConversationsTableData,
      PrefetchHooks Function()
    >;
typedef $$MessagesTableTableCreateCompanionBuilder =
    MessagesTableCompanion Function({
      Value<int> id,
      required int conversationId,
      required int senderId,
      required String senderName,
      Value<String> plaintextBody,
      Value<String> encryptedBody,
      Value<String> attachmentsJson,
      Value<String> messageType,
      Value<int> attachmentCount,
      Value<String> clientMessageId,
      Value<String> deliveryState,
      Value<String?> failureReason,
      Value<bool> isPending,
      required DateTime createdAt,
    });
typedef $$MessagesTableTableUpdateCompanionBuilder =
    MessagesTableCompanion Function({
      Value<int> id,
      Value<int> conversationId,
      Value<int> senderId,
      Value<String> senderName,
      Value<String> plaintextBody,
      Value<String> encryptedBody,
      Value<String> attachmentsJson,
      Value<String> messageType,
      Value<int> attachmentCount,
      Value<String> clientMessageId,
      Value<String> deliveryState,
      Value<String?> failureReason,
      Value<bool> isPending,
      Value<DateTime> createdAt,
    });

class $$MessagesTableTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plaintextBody => $composableBuilder(
    column: $table.plaintextBody,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedBody => $composableBuilder(
    column: $table.encryptedBody,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attachmentCount => $composableBuilder(
    column: $table.attachmentCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientMessageId => $composableBuilder(
    column: $table.clientMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPending => $composableBuilder(
    column: $table.isPending,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plaintextBody => $composableBuilder(
    column: $table.plaintextBody,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedBody => $composableBuilder(
    column: $table.encryptedBody,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attachmentCount => $composableBuilder(
    column: $table.attachmentCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientMessageId => $composableBuilder(
    column: $table.clientMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPending => $composableBuilder(
    column: $table.isPending,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plaintextBody => $composableBuilder(
    column: $table.plaintextBody,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryptedBody => $composableBuilder(
    column: $table.encryptedBody,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attachmentCount => $composableBuilder(
    column: $table.attachmentCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get clientMessageId => $composableBuilder(
    column: $table.clientMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPending =>
      $composableBuilder(column: $table.isPending, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$MessagesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTableTable,
          MessagesTableData,
          $$MessagesTableTableFilterComposer,
          $$MessagesTableTableOrderingComposer,
          $$MessagesTableTableAnnotationComposer,
          $$MessagesTableTableCreateCompanionBuilder,
          $$MessagesTableTableUpdateCompanionBuilder,
          (
            MessagesTableData,
            BaseReferences<
              _$AppDatabase,
              $MessagesTableTable,
              MessagesTableData
            >,
          ),
          MessagesTableData,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableTableManager(_$AppDatabase db, $MessagesTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> conversationId = const Value.absent(),
                Value<int> senderId = const Value.absent(),
                Value<String> senderName = const Value.absent(),
                Value<String> plaintextBody = const Value.absent(),
                Value<String> encryptedBody = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<String> messageType = const Value.absent(),
                Value<int> attachmentCount = const Value.absent(),
                Value<String> clientMessageId = const Value.absent(),
                Value<String> deliveryState = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<bool> isPending = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MessagesTableCompanion(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                senderName: senderName,
                plaintextBody: plaintextBody,
                encryptedBody: encryptedBody,
                attachmentsJson: attachmentsJson,
                messageType: messageType,
                attachmentCount: attachmentCount,
                clientMessageId: clientMessageId,
                deliveryState: deliveryState,
                failureReason: failureReason,
                isPending: isPending,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int conversationId,
                required int senderId,
                required String senderName,
                Value<String> plaintextBody = const Value.absent(),
                Value<String> encryptedBody = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<String> messageType = const Value.absent(),
                Value<int> attachmentCount = const Value.absent(),
                Value<String> clientMessageId = const Value.absent(),
                Value<String> deliveryState = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<bool> isPending = const Value.absent(),
                required DateTime createdAt,
              }) => MessagesTableCompanion.insert(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                senderName: senderName,
                plaintextBody: plaintextBody,
                encryptedBody: encryptedBody,
                attachmentsJson: attachmentsJson,
                messageType: messageType,
                attachmentCount: attachmentCount,
                clientMessageId: clientMessageId,
                deliveryState: deliveryState,
                failureReason: failureReason,
                isPending: isPending,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTableTable,
      MessagesTableData,
      $$MessagesTableTableFilterComposer,
      $$MessagesTableTableOrderingComposer,
      $$MessagesTableTableAnnotationComposer,
      $$MessagesTableTableCreateCompanionBuilder,
      $$MessagesTableTableUpdateCompanionBuilder,
      (
        MessagesTableData,
        BaseReferences<_$AppDatabase, $MessagesTableTable, MessagesTableData>,
      ),
      MessagesTableData,
      PrefetchHooks Function()
    >;
typedef $$QueuedOutgoingMessagesTableTableCreateCompanionBuilder =
    QueuedOutgoingMessagesTableCompanion Function({
      required String clientMessageId,
      required int conversationId,
      required int senderId,
      required String senderName,
      required String plaintext,
      Value<String> encryptedPayload,
      Value<String> messageType,
      Value<String> attachmentsJson,
      required DateTime createdAt,
      Value<int> retryCount,
      Value<DateTime?> nextRetryAt,
      Value<String> deliveryState,
      Value<String?> failureReason,
      Value<int> rowid,
    });
typedef $$QueuedOutgoingMessagesTableTableUpdateCompanionBuilder =
    QueuedOutgoingMessagesTableCompanion Function({
      Value<String> clientMessageId,
      Value<int> conversationId,
      Value<int> senderId,
      Value<String> senderName,
      Value<String> plaintext,
      Value<String> encryptedPayload,
      Value<String> messageType,
      Value<String> attachmentsJson,
      Value<DateTime> createdAt,
      Value<int> retryCount,
      Value<DateTime?> nextRetryAt,
      Value<String> deliveryState,
      Value<String?> failureReason,
      Value<int> rowid,
    });

class $$QueuedOutgoingMessagesTableTableFilterComposer
    extends Composer<_$AppDatabase, $QueuedOutgoingMessagesTableTable> {
  $$QueuedOutgoingMessagesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientMessageId => $composableBuilder(
    column: $table.clientMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plaintext => $composableBuilder(
    column: $table.plaintext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueuedOutgoingMessagesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $QueuedOutgoingMessagesTableTable> {
  $$QueuedOutgoingMessagesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientMessageId => $composableBuilder(
    column: $table.clientMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plaintext => $composableBuilder(
    column: $table.plaintext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueuedOutgoingMessagesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $QueuedOutgoingMessagesTableTable> {
  $$QueuedOutgoingMessagesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientMessageId => $composableBuilder(
    column: $table.clientMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plaintext =>
      $composableBuilder(column: $table.plaintext, builder: (column) => column);

  GeneratedColumn<String> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageType => $composableBuilder(
    column: $table.messageType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deliveryState => $composableBuilder(
    column: $table.deliveryState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );
}

class $$QueuedOutgoingMessagesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QueuedOutgoingMessagesTableTable,
          QueuedOutgoingMessagesTableData,
          $$QueuedOutgoingMessagesTableTableFilterComposer,
          $$QueuedOutgoingMessagesTableTableOrderingComposer,
          $$QueuedOutgoingMessagesTableTableAnnotationComposer,
          $$QueuedOutgoingMessagesTableTableCreateCompanionBuilder,
          $$QueuedOutgoingMessagesTableTableUpdateCompanionBuilder,
          (
            QueuedOutgoingMessagesTableData,
            BaseReferences<
              _$AppDatabase,
              $QueuedOutgoingMessagesTableTable,
              QueuedOutgoingMessagesTableData
            >,
          ),
          QueuedOutgoingMessagesTableData,
          PrefetchHooks Function()
        > {
  $$QueuedOutgoingMessagesTableTableTableManager(
    _$AppDatabase db,
    $QueuedOutgoingMessagesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueuedOutgoingMessagesTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$QueuedOutgoingMessagesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$QueuedOutgoingMessagesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> clientMessageId = const Value.absent(),
                Value<int> conversationId = const Value.absent(),
                Value<int> senderId = const Value.absent(),
                Value<String> senderName = const Value.absent(),
                Value<String> plaintext = const Value.absent(),
                Value<String> encryptedPayload = const Value.absent(),
                Value<String> messageType = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<String> deliveryState = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueuedOutgoingMessagesTableCompanion(
                clientMessageId: clientMessageId,
                conversationId: conversationId,
                senderId: senderId,
                senderName: senderName,
                plaintext: plaintext,
                encryptedPayload: encryptedPayload,
                messageType: messageType,
                attachmentsJson: attachmentsJson,
                createdAt: createdAt,
                retryCount: retryCount,
                nextRetryAt: nextRetryAt,
                deliveryState: deliveryState,
                failureReason: failureReason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientMessageId,
                required int conversationId,
                required int senderId,
                required String senderName,
                required String plaintext,
                Value<String> encryptedPayload = const Value.absent(),
                Value<String> messageType = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                required DateTime createdAt,
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<String> deliveryState = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueuedOutgoingMessagesTableCompanion.insert(
                clientMessageId: clientMessageId,
                conversationId: conversationId,
                senderId: senderId,
                senderName: senderName,
                plaintext: plaintext,
                encryptedPayload: encryptedPayload,
                messageType: messageType,
                attachmentsJson: attachmentsJson,
                createdAt: createdAt,
                retryCount: retryCount,
                nextRetryAt: nextRetryAt,
                deliveryState: deliveryState,
                failureReason: failureReason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueuedOutgoingMessagesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QueuedOutgoingMessagesTableTable,
      QueuedOutgoingMessagesTableData,
      $$QueuedOutgoingMessagesTableTableFilterComposer,
      $$QueuedOutgoingMessagesTableTableOrderingComposer,
      $$QueuedOutgoingMessagesTableTableAnnotationComposer,
      $$QueuedOutgoingMessagesTableTableCreateCompanionBuilder,
      $$QueuedOutgoingMessagesTableTableUpdateCompanionBuilder,
      (
        QueuedOutgoingMessagesTableData,
        BaseReferences<
          _$AppDatabase,
          $QueuedOutgoingMessagesTableTable,
          QueuedOutgoingMessagesTableData
        >,
      ),
      QueuedOutgoingMessagesTableData,
      PrefetchHooks Function()
    >;
typedef $$ConversationSyncStateTableTableCreateCompanionBuilder =
    ConversationSyncStateTableCompanion Function({
      Value<int> conversationId,
      Value<int?> lastMessageId,
      Value<DateTime?> lastSyncedAt,
    });
typedef $$ConversationSyncStateTableTableUpdateCompanionBuilder =
    ConversationSyncStateTableCompanion Function({
      Value<int> conversationId,
      Value<int?> lastMessageId,
      Value<DateTime?> lastSyncedAt,
    });

class $$ConversationSyncStateTableTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationSyncStateTableTable> {
  $$ConversationSyncStateTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationSyncStateTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationSyncStateTableTable> {
  $$ConversationSyncStateTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationSyncStateTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationSyncStateTableTable> {
  $$ConversationSyncStateTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );
}

class $$ConversationSyncStateTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationSyncStateTableTable,
          ConversationSyncStateTableData,
          $$ConversationSyncStateTableTableFilterComposer,
          $$ConversationSyncStateTableTableOrderingComposer,
          $$ConversationSyncStateTableTableAnnotationComposer,
          $$ConversationSyncStateTableTableCreateCompanionBuilder,
          $$ConversationSyncStateTableTableUpdateCompanionBuilder,
          (
            ConversationSyncStateTableData,
            BaseReferences<
              _$AppDatabase,
              $ConversationSyncStateTableTable,
              ConversationSyncStateTableData
            >,
          ),
          ConversationSyncStateTableData,
          PrefetchHooks Function()
        > {
  $$ConversationSyncStateTableTableTableManager(
    _$AppDatabase db,
    $ConversationSyncStateTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationSyncStateTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ConversationSyncStateTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ConversationSyncStateTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> conversationId = const Value.absent(),
                Value<int?> lastMessageId = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
              }) => ConversationSyncStateTableCompanion(
                conversationId: conversationId,
                lastMessageId: lastMessageId,
                lastSyncedAt: lastSyncedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> conversationId = const Value.absent(),
                Value<int?> lastMessageId = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
              }) => ConversationSyncStateTableCompanion.insert(
                conversationId: conversationId,
                lastMessageId: lastMessageId,
                lastSyncedAt: lastSyncedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationSyncStateTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationSyncStateTableTable,
      ConversationSyncStateTableData,
      $$ConversationSyncStateTableTableFilterComposer,
      $$ConversationSyncStateTableTableOrderingComposer,
      $$ConversationSyncStateTableTableAnnotationComposer,
      $$ConversationSyncStateTableTableCreateCompanionBuilder,
      $$ConversationSyncStateTableTableUpdateCompanionBuilder,
      (
        ConversationSyncStateTableData,
        BaseReferences<
          _$AppDatabase,
          $ConversationSyncStateTableTable,
          ConversationSyncStateTableData
        >,
      ),
      ConversationSyncStateTableData,
      PrefetchHooks Function()
    >;
typedef $$VerifiedKeysTableTableCreateCompanionBuilder =
    VerifiedKeysTableCompanion Function({
      required int userId,
      Value<String> deviceId,
      required String kind,
      Value<String?> verifiedFingerprint,
      Value<String?> lastSeenFingerprint,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$VerifiedKeysTableTableUpdateCompanionBuilder =
    VerifiedKeysTableCompanion Function({
      Value<int> userId,
      Value<String> deviceId,
      Value<String> kind,
      Value<String?> verifiedFingerprint,
      Value<String?> lastSeenFingerprint,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$VerifiedKeysTableTableFilterComposer
    extends Composer<_$AppDatabase, $VerifiedKeysTableTable> {
  $$VerifiedKeysTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verifiedFingerprint => $composableBuilder(
    column: $table.verifiedFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSeenFingerprint => $composableBuilder(
    column: $table.lastSeenFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VerifiedKeysTableTableOrderingComposer
    extends Composer<_$AppDatabase, $VerifiedKeysTableTable> {
  $$VerifiedKeysTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verifiedFingerprint => $composableBuilder(
    column: $table.verifiedFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSeenFingerprint => $composableBuilder(
    column: $table.lastSeenFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VerifiedKeysTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $VerifiedKeysTableTable> {
  $$VerifiedKeysTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get verifiedFingerprint => $composableBuilder(
    column: $table.verifiedFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastSeenFingerprint => $composableBuilder(
    column: $table.lastSeenFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$VerifiedKeysTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VerifiedKeysTableTable,
          VerifiedKeysTableData,
          $$VerifiedKeysTableTableFilterComposer,
          $$VerifiedKeysTableTableOrderingComposer,
          $$VerifiedKeysTableTableAnnotationComposer,
          $$VerifiedKeysTableTableCreateCompanionBuilder,
          $$VerifiedKeysTableTableUpdateCompanionBuilder,
          (
            VerifiedKeysTableData,
            BaseReferences<
              _$AppDatabase,
              $VerifiedKeysTableTable,
              VerifiedKeysTableData
            >,
          ),
          VerifiedKeysTableData,
          PrefetchHooks Function()
        > {
  $$VerifiedKeysTableTableTableManager(
    _$AppDatabase db,
    $VerifiedKeysTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VerifiedKeysTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VerifiedKeysTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VerifiedKeysTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> userId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> verifiedFingerprint = const Value.absent(),
                Value<String?> lastSeenFingerprint = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VerifiedKeysTableCompanion(
                userId: userId,
                deviceId: deviceId,
                kind: kind,
                verifiedFingerprint: verifiedFingerprint,
                lastSeenFingerprint: lastSeenFingerprint,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int userId,
                Value<String> deviceId = const Value.absent(),
                required String kind,
                Value<String?> verifiedFingerprint = const Value.absent(),
                Value<String?> lastSeenFingerprint = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VerifiedKeysTableCompanion.insert(
                userId: userId,
                deviceId: deviceId,
                kind: kind,
                verifiedFingerprint: verifiedFingerprint,
                lastSeenFingerprint: lastSeenFingerprint,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VerifiedKeysTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VerifiedKeysTableTable,
      VerifiedKeysTableData,
      $$VerifiedKeysTableTableFilterComposer,
      $$VerifiedKeysTableTableOrderingComposer,
      $$VerifiedKeysTableTableAnnotationComposer,
      $$VerifiedKeysTableTableCreateCompanionBuilder,
      $$VerifiedKeysTableTableUpdateCompanionBuilder,
      (
        VerifiedKeysTableData,
        BaseReferences<
          _$AppDatabase,
          $VerifiedKeysTableTable,
          VerifiedKeysTableData
        >,
      ),
      VerifiedKeysTableData,
      PrefetchHooks Function()
    >;
typedef $$DraftsTableTableCreateCompanionBuilder =
    DraftsTableCompanion Function({
      Value<int> conversationId,
      Value<String> draftText,
      required DateTime updatedAt,
    });
typedef $$DraftsTableTableUpdateCompanionBuilder =
    DraftsTableCompanion Function({
      Value<int> conversationId,
      Value<String> draftText,
      Value<DateTime> updatedAt,
    });

class $$DraftsTableTableFilterComposer
    extends Composer<_$AppDatabase, $DraftsTableTable> {
  $$DraftsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get draftText => $composableBuilder(
    column: $table.draftText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DraftsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DraftsTableTable> {
  $$DraftsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get draftText => $composableBuilder(
    column: $table.draftText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DraftsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DraftsTableTable> {
  $$DraftsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get draftText =>
      $composableBuilder(column: $table.draftText, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DraftsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DraftsTableTable,
          DraftsTableData,
          $$DraftsTableTableFilterComposer,
          $$DraftsTableTableOrderingComposer,
          $$DraftsTableTableAnnotationComposer,
          $$DraftsTableTableCreateCompanionBuilder,
          $$DraftsTableTableUpdateCompanionBuilder,
          (
            DraftsTableData,
            BaseReferences<_$AppDatabase, $DraftsTableTable, DraftsTableData>,
          ),
          DraftsTableData,
          PrefetchHooks Function()
        > {
  $$DraftsTableTableTableManager(_$AppDatabase db, $DraftsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DraftsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DraftsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DraftsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> conversationId = const Value.absent(),
                Value<String> draftText = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DraftsTableCompanion(
                conversationId: conversationId,
                draftText: draftText,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> conversationId = const Value.absent(),
                Value<String> draftText = const Value.absent(),
                required DateTime updatedAt,
              }) => DraftsTableCompanion.insert(
                conversationId: conversationId,
                draftText: draftText,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DraftsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DraftsTableTable,
      DraftsTableData,
      $$DraftsTableTableFilterComposer,
      $$DraftsTableTableOrderingComposer,
      $$DraftsTableTableAnnotationComposer,
      $$DraftsTableTableCreateCompanionBuilder,
      $$DraftsTableTableUpdateCompanionBuilder,
      (
        DraftsTableData,
        BaseReferences<_$AppDatabase, $DraftsTableTable, DraftsTableData>,
      ),
      DraftsTableData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConversationsTableTableTableManager get conversationsTable =>
      $$ConversationsTableTableTableManager(_db, _db.conversationsTable);
  $$MessagesTableTableTableManager get messagesTable =>
      $$MessagesTableTableTableManager(_db, _db.messagesTable);
  $$QueuedOutgoingMessagesTableTableTableManager
  get queuedOutgoingMessagesTable =>
      $$QueuedOutgoingMessagesTableTableTableManager(
        _db,
        _db.queuedOutgoingMessagesTable,
      );
  $$ConversationSyncStateTableTableTableManager
  get conversationSyncStateTable =>
      $$ConversationSyncStateTableTableTableManager(
        _db,
        _db.conversationSyncStateTable,
      );
  $$VerifiedKeysTableTableTableManager get verifiedKeysTable =>
      $$VerifiedKeysTableTableTableManager(_db, _db.verifiedKeysTable);
  $$DraftsTableTableTableManager get draftsTable =>
      $$DraftsTableTableTableManager(_db, _db.draftsTable);
}
