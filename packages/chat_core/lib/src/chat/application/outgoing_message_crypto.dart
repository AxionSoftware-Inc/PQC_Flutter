part of 'chat_services.dart';

// Crypto refresh methods implement the base contract.
// ignore_for_file: annotate_overrides

mixin _OutgoingMessageCrypto on _OutgoingMessageServiceBase {
  Future<CryptoProtocolCapabilities> _fetchCryptoProtocolCapabilities() async {
    final cached = _cachedCapabilities;
    final fetchedAt = _capabilitiesFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().toUtc().difference(fetchedAt) <
            _OutgoingMessageServiceBase._capabilitiesCacheLifetime) {
      return cached;
    }
    final inFlight = _capabilitiesFetchInFlight;
    if (inFlight != null) return inFlight;
    late final Future<CryptoProtocolCapabilities> operation;
    operation = remoteDataSource.fetchCryptoProtocolCapabilities().then((
      value,
    ) {
      _cachedCapabilities = value;
      _capabilitiesFetchedAt = DateTime.now().toUtc();
      return value;
    });
    _capabilitiesFetchInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_capabilitiesFetchInFlight, operation)) {
        _capabilitiesFetchInFlight = null;
      }
    });
  }

  Future<String> _encryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required String plaintext,
    required String messageId,
    required Future<void> Function() refreshUsers,
  }) async {
    try {
      return await cryptoService.encrypt(
        request: ChatCryptoRequest(
          currentUserId: currentUserId,
          conversation: conversation,
          usersById: usersById,
          messageId: messageId,
        ),
        plaintext: plaintext,
      );
    } catch (error) {
      if (error is! ChatEncryptionException) {
        rethrow;
      }
      // Group epochs cover every active participant device.  The cached
      // member/device snapshot can become stale when a member signs in or a
      // device key is registered just before this send.  Refresh it once and
      // rebuild the epoch instead of failing the send at the first attempt.
      if (conversation.isGroup) {
        await refreshUsers();
        return cryptoService.encrypt(
          request: ChatCryptoRequest(
            currentUserId: currentUserId,
            conversation: conversation,
            usersById: usersById,
            messageId: messageId,
          ),
          plaintext: plaintext,
        );
      }
      if (error.message != ChatCryptoService.peerPqcKeyNotReadyMessage) {
        rethrow;
      }
      await refreshUsers();
      return cryptoService.encrypt(
        request: ChatCryptoRequest(
          currentUserId: currentUserId,
          conversation: conversation,
          usersById: usersById,
          messageId: messageId,
        ),
        plaintext: plaintext,
      );
    }
  }

  Future<String> _decryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required String payload,
    int? senderId,
    required Future<void> Function() refreshUsers,
  }) async {
    final plaintext = await cryptoService.decrypt(
      request: ChatCryptoRequest(
        currentUserId: currentUserId,
        conversation: conversation,
        usersById: usersById,
        senderId: senderId,
      ),
      payload: payload,
    );
    if (conversation.isGroup ||
        !cryptoService.isDecryptFailureMarker(plaintext)) {
      return plaintext;
    }
    await refreshUsers();
    return cryptoService.decrypt(
      request: ChatCryptoRequest(
        currentUserId: currentUserId,
        conversation: conversation,
        usersById: usersById,
        senderId: senderId,
      ),
      payload: payload,
    );
  }
}
