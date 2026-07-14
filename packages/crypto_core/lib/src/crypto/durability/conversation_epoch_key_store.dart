import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../core/storage/local_secret_store.dart';

/// Account-scoped private-conversation epoch material for attachments.
/// LocalSecretStore entries are included in the enterprise recovery manifest.
class AttachmentConversationEpoch {
  const AttachmentConversationEpoch({
    required this.epochId,
    required this.secretKeyBytes,
  });

  final String epochId;
  final List<int> secretKeyBytes;
}

class ConversationEpochKeyStore {
  ConversationEpochKeyStore({
    LocalSecretStore? secretStore,
    Random? random,
    Uuid? uuid,
  }) : _secretStore = secretStore ?? LocalSecretStore(),
       _random = random ?? Random.secure(),
       _uuid = uuid ?? const Uuid();

  static const storagePrefix = 'attachment_conversation_epoch_v2_';

  final LocalSecretStore _secretStore;
  final Random _random;
  final Uuid _uuid;

  Future<AttachmentConversationEpoch> getOrCreatePrivateEpoch(
    int conversationId,
  ) async {
    final storageKey = '$storagePrefix$conversationId';
    final saved = await _secretStore.read(storageKey);
    if (saved != null && saved.isNotEmpty) {
      final document = jsonDecode(saved) as Map<String, dynamic>;
      final epochId = document['epoch_id'] as String? ?? '';
      final secret = document['secret_key_base64'] as String? ?? '';
      if (epochId.isNotEmpty && secret.isNotEmpty) {
        return AttachmentConversationEpoch(
          epochId: epochId,
          secretKeyBytes: base64Decode(secret),
        );
      }
      throw StateError('Stored attachment conversation epoch is malformed.');
    }
    final epoch = AttachmentConversationEpoch(
      epochId: _uuid.v4(),
      secretKeyBytes: List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    await _secretStore.write(
      key: storageKey,
      value: jsonEncode({
        'schema': 'attachment-conversation-epoch:v2',
        'epoch_id': epoch.epochId,
        'secret_key_base64': base64Encode(epoch.secretKeyBytes),
      }),
    );
    return epoch;
  }
}
