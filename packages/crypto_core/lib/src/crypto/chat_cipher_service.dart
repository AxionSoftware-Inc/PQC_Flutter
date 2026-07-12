import 'package:crypto_core/src/models/conversation.dart';
import 'chat_crypto_context.dart';
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

class RoutedChatCipherService implements ChatCipherService {
  RoutedChatCipherService({
    required List<ChatCipherAlgorithm> algorithms,
    required this._outboundMessageCache,
  }) : _algorithms = List.unmodifiable(algorithms);

  final List<ChatCipherAlgorithm> _algorithms;
  final OutboundMessageCache _outboundMessageCache;

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) async {
    final algorithm = _algorithms.firstWhere(
      (item) => item.supportsConversation(context.conversation),
      orElse: () => throw StateError(
        'No chat cipher algorithm is registered for this conversation.',
      ),
    );
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

    return payload;
  }
}
