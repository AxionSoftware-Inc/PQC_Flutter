import 'dart:convert';

import 'package:pqc_engine_sdk/pqc_engine_sdk.dart' as sdk;

import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/conversation.dart';

import 'group_key_store.dart';
import 'message_codec.dart';

/// Host adapter that delegates immutable V2 group message payloads to the SDK.
///
/// Group epoch persistence and its server envelopes remain host responsibilities:
/// they are account/device storage, not a portable protocol implementation.
class SdkV2GroupCipherMessageCodec extends GroupCipherMessageCodec {
  SdkV2GroupCipherMessageCodec({
    required super.groupKeyStore,
    sdk.PqcV2Engine? engine,
  }) : _groupKeyStore = groupKeyStore,
       _engine = engine ?? sdk.PqcV2Engine();

  final GroupKeyProvider _groupKeyStore;
  final sdk.PqcV2Engine _engine;

  @override
  Future<String> encrypt({
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    final key = await _groupKeyStore.getOrCreateKey(
      conversation: conversation,
      usersById: usersById,
    );
    return _engine.group.encrypt(
      conversation: sdk.PqcConversation(
        id: conversation.id,
        type: conversation.type,
      ),
      plaintext: plaintext,
      epoch: sdk.PqcGroupEpoch(
        epochId: key.keyId,
        secretKeyBytes: key.secretKeyBytes,
      ),
    );
  }

  @override
  Future<String> decrypt({
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    final epochId = _epochIdFor(payload, conversation);
    if (epochId == null) {
      return '[decrypt-error]';
    }
    final key = await _groupKeyStore.getExistingKey(
      conversation: conversation,
      usersById: usersById,
      requestedKeyId: epochId,
    );
    if (key == null) {
      return '[history-recovery-pending]';
    }
    final result = await _engine.group.decrypt(
      conversation: sdk.PqcConversation(
        id: conversation.id,
        type: conversation.type,
      ),
      payload: payload,
      epochsById: {
        key.keyId: sdk.PqcGroupEpoch(
          epochId: key.keyId,
          secretKeyBytes: key.secretKeyBytes,
        ),
      },
    );
    return switch (result) {
      sdk.PqcDecoded(:final plaintext) => plaintext,
      sdk.PqcDecodeError(failure: sdk.PqcDecodeFailure.keyMissing) =>
        '[history-recovery-pending]',
      _ => '[decrypt-error]',
    };
  }

  String? _epochIdFor(String payload, Conversation conversation) {
    const prefix = 'group:v2:';
    if (!payload.startsWith(prefix)) {
      return null;
    }
    try {
      final encoded = payload.substring(prefix.length);
      final padded = encoded.padRight(
        encoded.length + ((4 - encoded.length % 4) % 4),
        '=',
      );
      final document = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (document is! Map<String, dynamic> ||
          document['protocol_version'] != 2 ||
          document['algorithm'] != 'a256gcm+group-ml-kem-768' ||
          document['conversation_id'] != conversation.id ||
          document['conversation_type'] != conversation.type) {
        return null;
      }
      final epochId = document['group_epoch_id'];
      return epochId is String && epochId.isNotEmpty ? epochId : null;
    } catch (_) {
      return null;
    }
  }
}
