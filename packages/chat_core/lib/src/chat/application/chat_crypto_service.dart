part of 'chat_services.dart';

class ChatCryptoRequest {
  const ChatCryptoRequest({
    required this.currentUserId,
    required this.conversation,
    required this.usersById,
    this.messageId = '',
    this.senderId,
  });

  final int currentUserId;
  final Conversation conversation;
  final Map<int, AppUser> usersById;
  final String messageId;
  final int? senderId;
}

class ChatCryptoService {
  static const peerPqcKeyNotReadyMessage =
      'Peer PQC device key is not ready yet. Ask them to reopen the app.';
  static const decryptErrorMarker = '[decrypt-error]';
  static const decryptNeedsBackupRestoreMarker =
      '[decrypt-needs-backup-restore]';
  static const decryptKeyMissingMarker = '[decrypt-key-missing]';
  static const decryptHistoryRecoveryPendingMarker =
      '[history-recovery-pending]';

  const ChatCryptoService({required this.cipherService, this.cryptoCoreFacade});

  final ChatCipherService cipherService;
  final CryptoCoreFacade? cryptoCoreFacade;

  Future<void> assertLocalKeyHealth() async {
    final facade = cryptoCoreFacade;
    if (facade == null) return;
    final health = await facade.healthCheck();
    if (!health.healthy) {
      throw ChatEncryptionException(
        health.error ?? 'Local encryption keys are not healthy.',
      );
    }
  }

  Future<String> encrypt({
    required ChatCryptoRequest request,
    required String plaintext,
  }) async {
    await assertLocalKeyHealth();
    return cipherService.encrypt(
      context: ChatCryptoContext(
        currentUserId: request.currentUserId,
        conversation: request.conversation,
        usersById: request.usersById,
        messageId: request.messageId,
        senderId: request.senderId,
      ),
      plaintext: plaintext,
    );
  }

  Future<void> assertRemoteCanSend({
    required bool isGroup,
    required Iterable<String> remotePrefixes,
    Iterable<String> readableGroupEnvelopePrefixes = const [],
    Iterable<String> writableGroupEnvelopePrefixes = const [],
    Iterable<String> remoteAttachmentVersions = const [],
    bool hasAttachments = false,
  }) async {
    final facade = cryptoCoreFacade;
    if (facade == null) {
      if (hasAttachments &&
          !remoteAttachmentVersions.contains('attachment:v2')) {
        throw StateError(
          'Server did not advertise a supported attachment cipher version.',
        );
      }
      // The server capability gate still protects the wire protocol. Older
      // repository integrations may not expose the optional durability
      // facade, so message sending remains compatible for text payloads.
      return;
    }
    facade.assertRemoteSupportsActiveMessageWriter(
      isGroup: isGroup,
      remotePrefixes: remotePrefixes,
      remoteAttachmentVersions: remoteAttachmentVersions,
      hasAttachments: hasAttachments,
    );
    if (isGroup) {
      facade.configureGroupEnvelopeWriter(
        readablePrefixes: readableGroupEnvelopePrefixes,
        writablePrefixes: writableGroupEnvelopePrefixes,
      );
    }
  }

  String activeAttachmentCipherVersion({
    required bool isGroup,
    Iterable<String> remoteAttachmentVersions = const [],
  }) {
    return cryptoCoreFacade?.activeAttachmentCipherVersion(
          isGroup: isGroup,
          remoteAttachmentVersions: remoteAttachmentVersions,
        ) ??
        'attachment:v2';
  }

  Future<String> encryptAttachmentKeyWrap({
    required ChatCryptoRequest request,
    required AttachmentEncryptionDescriptor descriptor,
  }) => encrypt(request: request, plaintext: jsonEncode(descriptor.toJson()));

  Future<AttachmentEncryptionDescriptor> decryptAttachmentKeyWrap({
    required ChatCryptoRequest request,
    required String wrappedDescriptor,
  }) async {
    final plaintext = await decrypt(
      request: request,
      payload: wrappedDescriptor,
    );
    if (isDecryptFailureMarker(plaintext)) {
      throw ChatEncryptionException(
        'Attachment key is not available on this device.',
      );
    }
    final decoded = jsonDecode(plaintext);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Attachment key envelope is malformed.');
    }
    return AttachmentEncryptionDescriptor.fromJson(decoded);
  }

  Future<AttachmentEncryptionDescriptor> deriveAttachmentDescriptor({
    required ChatCryptoRequest request,
    required String attachmentId,
  }) async {
    final facade = cryptoCoreFacade;
    if (facade == null) {
      throw StateError('Crypto durability core is required for attachments.');
    }
    if (request.conversation.isGroup) {
      final epoch = await facade.groupKeyStore.getOrCreateKey(
        conversation: request.conversation,
        usersById: request.usersById,
      );
      return AttachmentCryptoService().deriveEpochBoundDescriptor(
        conversationEpochSecret: epoch.secretKeyBytes,
        conversationEpochId: epoch.keyId,
        attachmentId: attachmentId,
        manifestSequence: 0,
      );
    }
    final epoch = await facade.conversationEpochKeyStore
        .getOrCreatePrivateEpoch(request.conversation.id);
    return AttachmentCryptoService().deriveEpochBoundDescriptor(
      conversationEpochSecret: epoch.secretKeyBytes,
      conversationEpochId: epoch.epochId,
      attachmentId: attachmentId,
      manifestSequence: 0,
    );
  }

  Future<String> decrypt({
    required ChatCryptoRequest request,
    required String payload,
  }) async {
    final outcome = await decryptDetailed(request: request, payload: payload);
    return switch (outcome) {
      DecryptSuccess(:final plaintext) => plaintext,
      DecryptNeedsBackupRestore() => decryptNeedsBackupRestoreMarker,
      DecryptKeyMissing() => decryptKeyMissingMarker,
      DecryptFormatUnsupported() => decryptErrorMarker,
      DecryptCorruptedPayload() => decryptErrorMarker,
      _ => decryptErrorMarker,
    };
  }

  bool isDecryptFailureMarker(String value) {
    return value == decryptErrorMarker ||
        value == decryptNeedsBackupRestoreMarker ||
        value == decryptKeyMissingMarker ||
        value == decryptHistoryRecoveryPendingMarker;
  }

  Future<DecryptionOutcome> decryptDetailed({
    required ChatCryptoRequest request,
    required String payload,
  }) async {
    final plaintext = await cipherService.decrypt(
      context: ChatCryptoContext(
        currentUserId: request.currentUserId,
        conversation: request.conversation,
        usersById: request.usersById,
        messageId: request.messageId,
        senderId: request.senderId,
      ),
      payload: payload,
    );
    final cryptoCoreFacade = this.cryptoCoreFacade;
    if (cryptoCoreFacade == null) {
      if (!isDecryptFailureMarker(plaintext)) {
        return DecryptSuccess(
          plaintext: plaintext,
          format: const PayloadFormatDescriptor(
            formatId: 'legacy-pass-through',
            payloadKind: PayloadKind.privateMessage,
            prefix: '',
            introducedAtVersion: '0.0.0',
            decryptSupported: true,
          ),
        );
      }
      return DecryptCorruptedPayload(
        format: const PayloadFormatDescriptor(
          formatId: 'legacy-unknown',
          payloadKind: PayloadKind.privateMessage,
          prefix: '',
          introducedAtVersion: '0.0.0',
          decryptSupported: true,
        ),
      );
    }
    final format = cryptoCoreFacade.describePayload(payload);
    if (!isDecryptFailureMarker(plaintext)) {
      return DecryptSuccess(
        plaintext: plaintext,
        format:
            format ??
            const PayloadFormatDescriptor(
              formatId: 'plaintext-pass-through',
              payloadKind: PayloadKind.privateMessage,
              prefix: '',
              introducedAtVersion: '0.0.0',
              decryptSupported: true,
            ),
      );
    }
    return cryptoCoreFacade.classifyFailedDecrypt(payload);
  }
}

class ChatTrustService {
  const ChatTrustService({
    required this.keyVerificationService,
    required this.privateConversationSecurityCoordinator,
  });

  final KeyVerificationService keyVerificationService;
  final PrivateConversationSecurityCoordinator
  privateConversationSecurityCoordinator;

  Future<Map<int, UserKeyTrust>> buildUserTrustMap(Iterable<AppUser> users) {
    return keyVerificationService.buildUserTrustMap(users);
  }

  Future<ConversationTrustState> loadConversationTrust({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    final trust = await keyVerificationService.getConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    return ConversationTrustState(trust: trust);
  }

  Future<void> verifyConversationPeerKey({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    final trust = await keyVerificationService.getConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    final peerUser = trust.peerUser;
    if (peerUser == null) {
      return;
    }
    await keyVerificationService.verifyUser(peerUser);
  }

  Future<void> prepareForSend({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    return privateConversationSecurityCoordinator.prepareForSend(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
      onUserUpdated: (_) {},
    );
  }
}
