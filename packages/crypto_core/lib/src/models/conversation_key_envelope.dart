class ConversationKeyEnvelope {
  const ConversationKeyEnvelope({
    required this.keyId,
    required this.algorithm,
    required this.targetDeviceId,
    required this.senderDeviceId,
    required this.wrappedKey,
    required this.createdAt,
    required this.updatedAt,
  });

  final String keyId;
  final String algorithm;
  final String targetDeviceId;
  final String senderDeviceId;
  final String wrappedKey;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ConversationKeyEnvelope.fromJson(Map<String, dynamic> json) {
    return ConversationKeyEnvelope(
      keyId: json['key_id'] as String,
      algorithm: json['algorithm'] as String,
      targetDeviceId: json['target_device_id'] as String,
      senderDeviceId: json['sender_device_id'] as String,
      wrappedKey: json['wrapped_key'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class ConversationKeyEnvelopeUpload {
  const ConversationKeyEnvelopeUpload({
    required this.targetDeviceId,
    required this.wrappedKey,
  });

  final String targetDeviceId;
  final String wrappedKey;

  Map<String, dynamic> toJson() {
    return {'target_device_id': targetDeviceId, 'wrapped_key': wrappedKey};
  }
}
