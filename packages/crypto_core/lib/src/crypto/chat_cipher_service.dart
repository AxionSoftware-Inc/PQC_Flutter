import 'package:crypto_core/src/models/conversation.dart';
import 'chat_crypto_context.dart';
import 'durability/crypto_durability_models.dart';
import 'durability/protocol_version_manager.dart';
import 'outbound_message_cache.dart';

abstract class ChatCipherAlgorithm {
  bool supportsConversation(Conversation conversation);

  bool canDecrypt(String payload);

  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  });

  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  });
}

abstract class ChatCipherService {
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  });

  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  });
}

/// Optional writer capability implemented by production algorithms.
///
/// Keeping this separate from [ChatCipherAlgorithm] preserves compatibility
/// with host-provided decrypt-only algorithms and test doubles.
abstract interface class ChatCipherWriter {
  bool canWritePrefix(String prefix);
}

class RoutedChatCipherService implements ChatCipherService {
  RoutedChatCipherService({
    required List<ChatCipherAlgorithm> algorithms,
    required this._outboundMessageCache,
    this.protocolVersionManager,
  }) : _algorithms = List.unmodifiable(algorithms);

  final List<ChatCipherAlgorithm> _algorithms;
  final OutboundMessageCache _outboundMessageCache;
  final ProtocolVersionManager? protocolVersionManager;

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) async {
    final candidates = _algorithms.where(
      (item) => item.supportsConversation(context.conversation),
    );
    final manager = protocolVersionManager;
    final algorithm = manager == null
        ? candidates.firstOrNull
        : candidates.where((item) {
            if (item is! ChatCipherWriter) return false;
            final kind = context.conversation.isGroup
                ? PayloadKind.groupMessage
                : PayloadKind.privateMessage;
            return (item as ChatCipherWriter).canWritePrefix(
              manager.activeWriter(kind).prefix,
            );
          }).firstOrNull;
    if (algorithm == null) {
      throw StateError(
        'No chat cipher writer is registered for the active protocol and '
        'conversation kind.',
      );
    }
    final payload = await algorithm.encrypt(
      context: context,
      plaintext: plaintext,
    );
    await _outboundMessageCache.storePlaintext(
      payload: payload,
      plaintext: plaintext,
    );
    return payload;
  }

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async {
    final cachedPlaintext = await _outboundMessageCache.readPlaintext(payload);
    if (cachedPlaintext != null) {
      return cachedPlaintext;
    }

    for (final algorithm in _algorithms) {
      if (!algorithm.canDecrypt(payload)) {
        continue;
      }
      final plaintext = await algorithm.decrypt(
        context: context,
        payload: payload,
      );
      if (plaintext != '[decrypt-error]') {
        await _outboundMessageCache.storePlaintext(
          payload: payload,
          plaintext: plaintext,
        );
      }
      return plaintext;
    }

    // Ciphertext is never plaintext.  Returning an unrecognised wire payload
    // here made unsupported historical formats appear as chat text and hid the
    // actual compatibility failure from the durability layer.
    return '[decrypt-error]';
  }
}
