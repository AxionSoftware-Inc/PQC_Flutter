class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    required this.title,
    required this.participantIds,
    required this.lastMessagePreview,
    required this.updatedAt,
  });

  final int id;
  final String type;
  final String title;
  final List<int> participantIds;
  final String lastMessagePreview;
  final DateTime updatedAt;

  bool get isGroup => type == 'group';

  String get keyMaterial {
    final sortedParticipants = [...participantIds]..sort();
    return '$id|$type|${sortedParticipants.join(",")}';
  }

  Conversation copyWith({
    int? id,
    String? type,
    String? title,
    List<int>? participantIds,
    String? lastMessagePreview,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      participantIds: participantIds ?? this.participantIds,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as int,
      type: json['type'] as String,
      title: json['title'] as String? ?? '',
      participantIds: (json['participant_ids'] as List<dynamic>).cast<int>(),
      lastMessagePreview: json['last_message_preview'] as String? ?? '',
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
