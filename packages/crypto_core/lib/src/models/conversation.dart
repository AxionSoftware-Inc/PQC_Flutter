class Conversation {
  const Conversation({
    required this.id,
    this.workspaceId = 0,
    required this.type,
    this.module = 'chat',
    this.moduleKey = '',
    required this.title,
    required this.participantIds,
    required this.lastMessagePreview,
    this.unreadCount = 0,
    required this.updatedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? updatedAt;

  final int id;
  final int workspaceId;
  final String type;
  final String module;
  final String moduleKey;
  final String title;
  final List<int> participantIds;
  final String lastMessagePreview;
  final int unreadCount;
  final DateTime updatedAt;
  final DateTime createdAt;

  bool get isGroup => type == 'group';

  bool get isKpi => module == 'kpi';

  String get keyMaterial {
    final sortedParticipants = [...participantIds]..sort();
    return '$id|$type|${sortedParticipants.join(",")}';
  }

  Conversation copyWith({
    int? id,
    int? workspaceId,
    String? type,
    String? module,
    String? moduleKey,
    String? title,
    List<int>? participantIds,
    String? lastMessagePreview,
    int? unreadCount,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      type: type ?? this.type,
      module: module ?? this.module,
      moduleKey: moduleKey ?? this.moduleKey,
      title: title ?? this.title,
      participantIds: participantIds ?? this.participantIds,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as int,
      workspaceId: json['workspace_id'] as int? ?? 0,
      type: json['type'] as String,
      module: json['module'] as String? ?? 'chat',
      moduleKey: json['module_key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      participantIds: (json['participant_ids'] as List<dynamic>).cast<int>(),
      lastMessagePreview: json['last_message_preview'] as String? ?? '',
      unreadCount: json['unread_count'] as int? ?? 0,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      createdAt: DateTime.parse(
        (json['created_at'] as String?) ?? json['updated_at'] as String,
      ),
    );
  }
}
