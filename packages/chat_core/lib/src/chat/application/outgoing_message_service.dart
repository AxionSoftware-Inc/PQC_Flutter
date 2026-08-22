part of 'chat_services.dart';

// The base contract is implemented by the pipeline/attachment/crypto mixins.
// ignore_for_file: unused_element, unused_element_parameter

abstract class _OutgoingMessageServiceBase {
  _OutgoingMessageServiceBase({
    required this.remoteDataSource,
    required this.cryptoService,
    required this.localStore,
    required this.outboxStore,
    this.attachmentTransferFacade,
    this.onCryptoStateChanged,
  });

  final ChatRemoteDataSource remoteDataSource;
  final ChatCryptoService cryptoService;
  final ChatLocalStore localStore;
  final OutboxStore outboxStore;
  final AttachmentTransferFacade? attachmentTransferFacade;
  final Future<void> Function()? onCryptoStateChanged;
  CryptoProtocolCapabilities? _cachedCapabilities;
  DateTime? _capabilitiesFetchedAt;

  static const _capabilitiesCacheLifetime = Duration(minutes: 5);
  static const _attachmentChunkSize = 256 * 1024;
  final Map<String, Future<ChatMessage>> _inFlightSends = {};
  Future<CryptoProtocolCapabilities>? _capabilitiesFetchInFlight;

  Future<ChatMessage> _sendQueuedMessage(
    QueuedOutgoingMessage queued, {
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation)
    persistConversation,
    SendPipelineProgress? onProgress,
  });

  Future<ChatMessage> _sendQueuedMessageOnce(
    QueuedOutgoingMessage queued, {
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation)
    persistConversation,
    SendPipelineProgress? onProgress,
  });

  Future<ChatAttachment> _uploadEncryptedAttachment({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required String clientMessageId,
    required int attachmentIndex,
    required PendingAttachmentUpload attachment,
    required String cipherVersion,
  });

  Future<File> _materializeAttachmentFile(
    PendingAttachmentUpload attachment, {
    required void Function(File file) onTemporaryFile,
  });

  Future<CryptoProtocolCapabilities> _fetchCryptoProtocolCapabilities();

  Future<String> _encryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required String plaintext,
    required String messageId,
    required Future<void> Function() refreshUsers,
  });

  Future<String> _decryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required String payload,
    int? senderId,
    required Future<void> Function() refreshUsers,
  });
}

class OutgoingMessageService extends _OutgoingMessageServiceBase
    with
        _OutgoingMessageQueue,
        _OutgoingMessageDelivery,
        _OutgoingMessageAttachments,
        _OutgoingMessageCrypto {
  OutgoingMessageService({
    required super.remoteDataSource,
    required super.cryptoService,
    required super.localStore,
    required super.outboxStore,
    super.attachmentTransferFacade,
    super.onCryptoStateChanged,
  });

  Future<void> warmProtocolCapabilities() async {
    await _fetchCryptoProtocolCapabilities();
  }
}
