import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_ui_preferences_store.dart';
import '../../crypto/chat_crypto_exceptions.dart';
import '../../crypto/durability/crypto_core_facade.dart';
import '../../security/key_verification_service.dart';
import '../application/chat_controllers.dart';
import '../application/chat_facade.dart';
import '../application/chat_models.dart';
import '../application/chat_services.dart';
import '../../transfers/application/attachment_transfer.dart';
import 'chat_local_image.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.currentUserId,
    required this.conversation,
    required this.title,
    required this.chatFacade,
    required this.cryptoCoreFacade,
    required this.onUnauthorized,
  });

  final int currentUserId;
  final Conversation conversation;
  final String title;
  final ChatFacade chatFacade;
  final CryptoCoreFacade cryptoCoreFacade;
  final Future<void> Function() onUnauthorized;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final ChatConversationController _controller;
  final AppDatabase _database = AppDatabase();
  final LocalUiPreferencesStore _preferencesStore = LocalUiPreferencesStore();
  List<_SelectedAttachment> _selectedAttachments = const [];
  Timer? _draftDebounce;
  bool _keepDrafts = true;
  bool _showSecurityDetails = false;
  bool _showTransferDetails = false;
  final Map<int, String> _downloadedAttachmentPaths = <int, String>{};
  int _lastMessageCount = 0;
  bool _hasRenderedMessages = false;

  @override
  void initState() {
    super.initState();
    _controller = ChatConversationController(
      chatFacade: widget.chatFacade,
      currentUserId: widget.currentUserId,
      conversation: widget.conversation,
    )..addListener(_onControllerChanged);
    _messageController.addListener(_queueDraftSave);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _draftDebounce?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _loadDraftPreferences();
      await _controller.initialize();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.onUnauthorized();
        return;
      }
      // The controller keeps the existing/local history and exposes the
      // failure in its status banner. Do not let the unawaited initialization
      // escape as a framework error and cause the page to restart.
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadDraftPreferences() async {
    final preferences = await _preferencesStore.readAppPreferences();
    _keepDrafts = preferences.keepDrafts;
    if (!_keepDrafts) {
      return;
    }
    final existing = await _database.readDraft(widget.conversation.id);
    if (existing == null || existing.draftText.trim().isEmpty) {
      return;
    }
    _messageController.text = existing.draftText;
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final messageCount = _controller.messages.length;
    final isNearBottom =
        !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <
            96;
    final shouldJump =
        !_hasRenderedMessages ||
        (messageCount > _lastMessageCount && isNearBottom);
    _lastMessageCount = messageCount;
    _hasRenderedMessages = true;
    for (final transfer in _controller.attachmentTransfers) {
      if (transfer.attachmentId != null && transfer.localPath != null) {
        _downloadedAttachmentPaths[transfer.attachmentId!] =
            transfer.localPath!;
      }
    }
    setState(() {});
    if (shouldJump) {
      _jumpToBottom();
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _selectedAttachments.isEmpty) ||
        _controller.isSending) {
      return;
    }

    try {
      await _controller.sendMessage(
        SendMessageCommand(
          conversation: widget.conversation,
          currentUserId: widget.currentUserId,
          text: text,
          messageType: _selectedAttachments.isEmpty
              ? 'text'
              : _selectedAttachments.any((item) => item.isImage)
              ? 'image'
              : 'file',
          attachments: _selectedAttachments
              .map(
                (item) => PendingAttachmentUpload(
                  filename: item.name,
                  bytes: item.bytes,
                  filePath: item.filePath,
                  sizeBytes: item.sizeBytes,
                  mimeType: item.mimeType,
                ),
              )
              .toList(),
        ),
      );
      _messageController.clear();
      await _database.upsertDraft(
        DraftsTableCompanion(
          conversationId: drift.Value(widget.conversation.id),
          draftText: const drift.Value(''),
          updatedAt: drift.Value(DateTime.now().toUtc()),
        ),
      );
      setState(() {
        _selectedAttachments = const [];
      });
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      final message = error is ChatEncryptionException
          ? error.message
          : error.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || !mounted) {
      return;
    }
    final picked = <_SelectedAttachment>[];
    for (final file in result.files) {
      if (file.size <= 0) {
        continue;
      }
      if (file.size > TransferPolicy.maxAttachmentBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${file.name} too large. Max ${TransferPolicy.formatBytes(TransferPolicy.maxAttachmentBytes)} per file.',
            ),
          ),
        );
        continue;
      }
      final hasBytes = file.bytes != null && file.bytes!.isNotEmpty;
      final hasPath = file.path != null && file.path!.trim().isNotEmpty;
      if (!hasBytes && !hasPath) {
        continue;
      }
      picked.add(
        _SelectedAttachment(
          name: file.name,
          bytes: file.bytes,
          filePath: file.path,
          sizeBytes: file.size,
          mimeType: _inferMimeType(file.name),
        ),
      );
    }
    if (picked.isEmpty) {
      return;
    }
    setState(() {
      _selectedAttachments = [..._selectedAttachments, ...picked];
    });
  }

  void _removeSelectedAttachment(_SelectedAttachment attachment) {
    setState(() {
      _selectedAttachments = _selectedAttachments
          .where((item) => item != attachment)
          .toList();
    });
  }

  Future<void> _retryMessage(ChatMessage message) async {
    try {
      await _controller.retryMessage(message.clientMessageId);
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.onUnauthorized();
      }
    }
  }

  Future<void> _verifyCurrentKey() async {
    try {
      await _controller.verifyCurrentKey();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Current key verified.')));
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.onUnauthorized();
      }
    }
  }

  void _queueDraftSave() {
    if (!_keepDrafts) {
      return;
    }
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 350), () async {
      await _database.upsertDraft(
        DraftsTableCompanion(
          conversationId: drift.Value(widget.conversation.id),
          draftText: drift.Value(_messageController.text),
          updatedAt: drift.Value(DateTime.now().toUtc()),
        ),
      );
    });
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversationTrust = _controller.trust?.trust;
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final brand = AppBrandScope.of(context).brand;
    final needsBackupRestore = _controller.messages.any(
      (item) =>
          item.body == ChatCryptoService.decryptNeedsBackupRestoreMarker ||
          item.body == ChatCryptoService.decryptKeyMissingMarker,
    );
    return AppScaffold(
      appBar: AppBar(toolbarHeight: 0),
      body: Column(
        children: [
          _ConversationHeader(
            title: widget.title,
            conversation: widget.conversation,
            trust: conversationTrust,
            brandLabel: brand?.label,
            onBack: () => Navigator.of(context).maybePop(),
            onOpenDetails: _showConversationDetails,
            onVerify:
                !widget.conversation.isGroup &&
                    conversationTrust?.isAvailable == true
                ? _verifyCurrentKey
                : null,
            transferCount: _controller.attachmentTransfers.length,
          ),
          if (_controller.isLoading) const LinearProgressIndicator(),
          if (_controller.error != null)
            Padding(
              padding: EdgeInsets.all(spacing.sm),
              child: AppStatusBanner(
                message: _controller.error!,
                tone: AppStatusTone.danger,
              ),
            ),
          if (!widget.conversation.isGroup && conversationTrust != null)
            Column(
              children: [
                _SecurityBanner(
                  trust: conversationTrust,
                  onVerify: _verifyCurrentKey,
                  isExpanded: _showSecurityDetails,
                  onToggleExpanded: () {
                    setState(() {
                      _showSecurityDetails = !_showSecurityDetails;
                    });
                  },
                ),
                if (_showSecurityDetails)
                  _SecurityDetailCard(trust: conversationTrust),
              ],
            ),
          if (needsBackupRestore)
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.sm,
                spacing.sm,
                spacing.sm,
                0,
              ),
              child: const AppStatusBanner(
                message:
                    'Ba’zi eski xabarlar uchun backup restore kerak bo‘lishi mumkin. Settings > Backup & Recovery bo‘limidan tiklash mumkin.',
                tone: AppStatusTone.warning,
              ),
            ),
          Expanded(
            child: _controller.isLoading && _controller.messages.isEmpty
                ? _buildLoadingState()
                : _controller.messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: AppEmptyState(
                        message:
                            'Conversation hali bo‘sh. Birinchi xabarni yuboring.',
                        icon: Icons.chat_bubble_outline_rounded,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      spacing.sm,
                      spacing.sm,
                      spacing.sm,
                      spacing.xs,
                    ),
                    itemCount: _controller.messages.length,
                    itemBuilder: (context, index) {
                      final message = _controller.messages[index];
                      final isMine = message.senderId == widget.currentUserId;
                      return _buildMessageItem(
                        message: message,
                        isMine: isMine,
                        colors: colors,
                        spacing: spacing,
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.sm,
                spacing.xs,
                spacing.sm,
                spacing.sm,
              ),
              child: Column(
                children: [
                  if (_controller.attachmentTransfers.isNotEmpty)
                    _buildTransferSection(
                      expanded: _showTransferDetails,
                      onToggleExpanded: () {
                        setState(() {
                          _showTransferDetails = !_showTransferDetails;
                        });
                      },
                    ),
                  if (_controller.attachmentTransfers.isNotEmpty)
                    SizedBox(height: spacing.sm),
                  if (_selectedAttachments.isNotEmpty)
                    _buildSelectedAttachmentTray(),
                  if (_selectedAttachments.isNotEmpty)
                    SizedBox(height: spacing.xs),
                  AppSurfaceCard(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.xs,
                      vertical: spacing.xs,
                    ),
                    backgroundColor: colors.surface.withValues(alpha: 0.96),
                    child: Row(
                      children: [
                        _ComposerActionButton(
                          icon: Icons.add_rounded,
                          onPressed: _controller.isSending
                              ? null
                              : _pickAttachments,
                        ),
                        Expanded(
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              inputDecorationTheme: Theme.of(context)
                                  .inputDecorationTheme
                                  .copyWith(
                                    filled: false,
                                    fillColor: Colors.transparent,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: spacing.sm,
                                      vertical: spacing.xs,
                                    ),
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    border: InputBorder.none,
                                  ),
                            ),
                            child: AppTextField(
                              controller: _messageController,
                              hintText: 'Message',
                              maxLines: 4,
                              minLines: 1,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        SizedBox(width: spacing.xs),
                        _ComposerSendButton(
                          isSending: _controller.isSending,
                          onPressed: _controller.isSending
                              ? null
                              : _sendMessage,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(ChatMessage message) {
    switch (message.deliveryState) {
      case MessageDeliveryState.pending:
        return 'Sending...';
      case MessageDeliveryState.failedRetryable:
        return message.failureReason ?? 'Send failed. Retry available.';
      case MessageDeliveryState.failedPermanent:
        return message.failureReason ?? 'Send failed permanently.';
      case MessageDeliveryState.sent:
        return '';
    }
  }

  Future<void> _showConversationDetails() {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: _ConversationProfilePage(
            title: widget.title,
            conversation: widget.conversation,
            trust: _controller.trust?.trust,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedAttachmentTray() {
    final spacing = context.appSpacing;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedAttachments.length,
        separatorBuilder: (_, _) => SizedBox(width: spacing.xs),
        itemBuilder: (context, index) {
          final item = _selectedAttachments[index];
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.sm,
              vertical: spacing.xs,
            ),
            decoration: BoxDecoration(
              color: context.appColors.surfaceMuted,
              borderRadius: BorderRadius.circular(context.appRadii.pill),
              border: Border.all(color: context.appColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.isImage ? Icons.image_outlined : Icons.attach_file,
                  size: 16,
                  color: context.appColors.textMuted,
                ),
                SizedBox(width: spacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    '${item.name} (${_formatBytes(item.sizeBytes)})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SizedBox(width: spacing.xs),
                InkWell(
                  onTap: () => _removeSelectedAttachment(item),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    final spacing = context.appSpacing;
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) {
        final isMine = index.isEven;
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            margin: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.xs,
            ),
            child: AppSurfaceCard(
              backgroundColor: isMine
                  ? context.appColors.chatMine.withValues(alpha: 0.25)
                  : context.appColors.surface,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeletonBlock(height: 12, width: 80),
                  SizedBox(height: 10),
                  AppSkeletonBlock(height: 14),
                  SizedBox(height: 10),
                  AppSkeletonBlock(height: 14, width: 180),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageItem({
    required ChatMessage message,
    required bool isMine,
    required AppColors colors,
    required AppSpacing spacing,
  }) {
    final isDecryptNeedsRestore =
        message.body == ChatCryptoService.decryptNeedsBackupRestoreMarker ||
        message.body == ChatCryptoService.decryptKeyMissingMarker;
    final isDecryptError = message.body == ChatCryptoService.decryptErrorMarker;
    final isImageOnly =
        message.attachments.length == 1 &&
        message.attachments.single.mimeType.startsWith('image/') &&
        message.body.trim().isEmpty &&
        !isDecryptNeedsRestore &&
        !isDecryptError;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: spacing.xs,
          vertical: spacing.xs,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: isImageOnly
                      ? EdgeInsets.zero
                      : EdgeInsets.symmetric(
                          horizontal: spacing.md,
                          vertical: spacing.sm,
                        ),
                  decoration: BoxDecoration(
                    color: isImageOnly
                        ? Colors.transparent
                        : isMine
                        ? colors.chatMine
                        : colors.chatPeer,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(context.appRadii.md),
                      topRight: Radius.circular(context.appRadii.md),
                      bottomLeft: Radius.circular(
                        isMine ? context.appRadii.md : context.appRadii.sm,
                      ),
                      bottomRight: Radius.circular(
                        isMine ? context.appRadii.sm : context.appRadii.md,
                      ),
                    ),
                    border: isImageOnly
                        ? null
                        : Border.all(
                            color: isMine
                                ? colors.primary.withValues(alpha: 0.16)
                                : colors.border,
                          ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMine && !isImageOnly) ...[
                        Text(
                          message.senderName,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: colors.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        SizedBox(height: spacing.xs),
                      ],
                      if (message.attachments.isNotEmpty) ...[
                        Wrap(
                          spacing: spacing.xs,
                          runSpacing: spacing.xs,
                          children: message.attachments
                              .map(
                                (attachment) => _buildAttachmentChip(
                                  attachment,
                                  message: message,
                                  isMine: isMine,
                                  showDeliveryOverlay: isImageOnly,
                                ),
                              )
                              .toList(),
                        ),
                        if (message.body.trim().isNotEmpty)
                          SizedBox(height: spacing.sm),
                      ],
                      if (isDecryptNeedsRestore)
                        Text(
                          'Historical decrypt unavailable on this device. Restore backup to read this message.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: isMine ? Colors.white : null,
                                height: 1.35,
                              ),
                        )
                      else if (isDecryptError)
                        Text(
                          'Unable to decrypt this message.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: isMine ? Colors.white : null,
                                height: 1.35,
                              ),
                        )
                      else if (message.body.trim().isNotEmpty)
                        Text(
                          message.body,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: isMine ? Colors.white : null,
                                height: 1.35,
                              ),
                        ),
                      if (!isImageOnly) ...[
                        SizedBox(height: spacing.xs),
                        _buildMessageFooter(message: message, isMine: isMine),
                      ],
                    ],
                  ),
                ),
                if (message.canRetry)
                  TextButton(
                    onPressed: () => _retryMessage(message),
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentChip(
    ChatAttachment attachment, {
    ChatMessage? message,
    bool isMine = false,
    bool showDeliveryOverlay = false,
  }) {
    final transfer = _controller.findDownloadTransfer(attachment.id);
    final isBusy =
        transfer != null &&
        transfer.status != AttachmentTransferStatus.completed &&
        transfer.status != AttachmentTransferStatus.failed;
    final isImage = attachment.mimeType.startsWith('image/');
    final localPath = _downloadedAttachmentPaths[attachment.id];
    final label = transfer == null
        ? '${attachment.filename} (${_formatBytes(attachment.sizeBytes)})'
        : '${attachment.filename} • ${_transferStatusLabel(transfer)}';
    final onPressed = isBusy
        ? () async {
            await _controller.pauseTransfer(transfer.localId);
          }
        : () async {
            try {
              final path = await _controller.downloadAttachment(attachment);
              if (!mounted) {
                return;
              }
              if (isImage) {
                _downloadedAttachmentPaths[attachment.id] = path;
                if (mounted) setState(() {});
                await _showImageLightbox(attachment.filename, path);
                return;
              }
              if (kIsWeb) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Attachment downloaded to $path')),
                );
                return;
              }
              final result = await OpenFilex.open(path);
              if (!mounted) {
                return;
              }
              if (result.type != ResultType.done) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result.message.isEmpty
                          ? 'Downloaded, but no app can open this file.'
                          : result.message,
                    ),
                  ),
                );
              }
            } catch (error) {
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(error.toString())));
            }
          };
    if (isImage) {
      if (localPath != null && localPath.isNotEmpty) {
        return Stack(
          children: [
            InkWell(
              onTap: () => _showImageLightbox(attachment.filename, localPath),
              borderRadius: BorderRadius.circular(context.appRadii.sm),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(context.appRadii.sm),
                child: SizedBox(
                  width: 248,
                  child: buildChatLocalImage(context, localPath),
                ),
              ),
            ),
            if (showDeliveryOverlay && message != null)
              _buildImageDeliveryOverlay(message: message, isMine: isMine),
          ],
        );
      }
      return Stack(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(context.appRadii.sm),
              child: Ink(
                width: 248,
                height: 172,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(context.appRadii.sm),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.photo_outlined, size: 34),
                    SizedBox(height: context.appSpacing.xs),
                    Text(
                      'Tap to load photo',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showDeliveryOverlay && message != null)
            _buildImageDeliveryOverlay(message: message, isMine: isMine),
        ],
      );
    }
    return ActionChip(
      avatar: const Icon(Icons.insert_drive_file_outlined, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }

  Widget _buildMessageFooter({
    required ChatMessage message,
    required bool isMine,
  }) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (message.deliveryState != MessageDeliveryState.sent)
            Text(
              _statusLabel(message),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.72)
                    : colors.textMuted,
              ),
            ),
          Text(
            _formatMessageTime(message.createdAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isMine
                  ? Colors.white.withValues(alpha: 0.68)
                  : colors.textMuted,
            ),
          ),
          if (isMine)
            Icon(
              message.deliveryState == MessageDeliveryState.sent
                  ? Icons.done_all_rounded
                  : Icons.schedule_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: 0.75),
            ),
        ],
      ),
    );
  }

  Widget _buildImageDeliveryOverlay({
    required ChatMessage message,
    required bool isMine,
  }) {
    return Positioned(
      right: 6,
      bottom: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(context.appRadii.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatMessageTime(message.createdAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 3),
                Icon(
                  message.deliveryState == MessageDeliveryState.sent
                      ? Icons.done_all_rounded
                      : Icons.schedule_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showImageLightbox(String title, String path) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(child: buildChatLocalImageViewer(dialogContext, path)),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  tooltip: 'Close image',
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferSection({
    required bool expanded,
    required VoidCallback onToggleExpanded,
  }) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final activeCount = _controller.attachmentTransfers
        .where((item) => item.status != AttachmentTransferStatus.completed)
        .length;
    return AppSurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(context.appRadii.md),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Row(
                children: [
                  Icon(
                    Icons.sync_alt_rounded,
                    size: 18,
                    color: colors.textMuted,
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transfers',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          activeCount > 0
                              ? '$activeCount active • ${_controller.attachmentTransfers.length} total'
                              : '${_controller.attachmentTransfers.length} recent transfers',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            SizedBox(height: spacing.sm),
            ..._controller.attachmentTransfers.map(
              (transfer) => Padding(
                padding: EdgeInsets.only(bottom: spacing.sm),
                child: _buildTransferTile(transfer),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransferTile(AttachmentTransferState transfer) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final progress = transfer.progress.fraction.clamp(0, 1).toDouble();
    final isTerminal =
        transfer.status == AttachmentTransferStatus.completed ||
        transfer.status == AttachmentTransferStatus.failed;
    return Container(
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.appRadii.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                transfer.direction == AttachmentTransferDirection.upload
                    ? Icons.upload_file_rounded
                    : Icons.download_rounded,
                size: 18,
                color: colors.textMuted,
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text(
                  transfer.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                _transferPercentLabel(transfer),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Text(
            _transferStatusLabel(transfer),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
          SizedBox(height: spacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(context.appRadii.sm),
            child: LinearProgressIndicator(
              value: isTerminal ? 1 : progress,
              minHeight: 4,
            ),
          ),
          SizedBox(height: spacing.xs),
          Wrap(
            spacing: spacing.xs,
            runSpacing: spacing.xs,
            children: [
              if (!isTerminal &&
                  transfer.status != AttachmentTransferStatus.paused)
                AppSecondaryButton(
                  onPressed: () => _controller.pauseTransfer(transfer.localId),
                  label: const Text('Pause'),
                ),
              if (transfer.status == AttachmentTransferStatus.paused)
                AppPrimaryButton(
                  onPressed: () => _resumeTransfer(transfer),
                  label: const Text('Resume'),
                ),
              if (transfer.status == AttachmentTransferStatus.failed)
                AppPrimaryButton(
                  onPressed: () => _resumeTransfer(transfer),
                  label: const Text('Retry'),
                ),
              if (transfer.status == AttachmentTransferStatus.completed)
                AppSecondaryButton(
                  onPressed: () =>
                      _controller.clearCompletedTransfer(transfer.localId),
                  label: const Text('Clear'),
                ),
              AppSecondaryButton(
                onPressed: () => _controller.cancelTransfer(transfer.localId),
                label: const Text('Cancel'),
              ),
            ],
          ),
          if (transfer.error?.isNotEmpty == true) ...[
            SizedBox(height: spacing.xs),
            Text(
              transfer.error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _resumeTransfer(AttachmentTransferState transfer) async {
    try {
      await _controller.resumeTransfer(transfer.localId);
      if (transfer.direction == AttachmentTransferDirection.download &&
          transfer.attachmentId != null) {
        final attachments = _controller.messages.expand(
          (item) => item.attachments,
        );
        for (final attachment in attachments) {
          if (attachment.id == transfer.attachmentId) {
            await _controller.downloadAttachment(attachment);
            break;
          }
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _transferPercentLabel(AttachmentTransferState transfer) {
    final fraction = transfer.progress.fraction;
    if (transfer.progress.totalChunks <= 0) {
      return '';
    }
    return '${(fraction * 100).round()}%';
  }

  String _transferStatusLabel(AttachmentTransferState transfer) {
    switch (transfer.status) {
      case AttachmentTransferStatus.queued:
        return transfer.direction == AttachmentTransferDirection.upload
            ? 'Queued for upload'
            : 'Queued for download';
      case AttachmentTransferStatus.encrypting:
        return 'Encrypting';
      case AttachmentTransferStatus.uploading:
        return 'Uploading';
      case AttachmentTransferStatus.downloading:
        return 'Downloading';
      case AttachmentTransferStatus.paused:
        return 'Paused';
      case AttachmentTransferStatus.retrying:
        return 'Retrying';
      case AttachmentTransferStatus.verifying:
        return 'Verifying';
      case AttachmentTransferStatus.completed:
        return transfer.direction == AttachmentTransferDirection.upload
            ? 'Uploaded'
            : 'Downloaded';
      case AttachmentTransferStatus.failed:
        return 'Failed';
    }
  }

  String _formatBytes(int bytes) {
    return TransferPolicy.formatBytes(bytes);
  }

  String _formatMessageTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _inferMimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }
}

class _SelectedAttachment {
  const _SelectedAttachment({
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
    this.bytes,
    this.filePath,
  });

  final String name;
  final List<int>? bytes;
  final String? filePath;
  final int sizeBytes;
  final String mimeType;

  bool get isImage => mimeType.startsWith('image/');
}

class _ComposerActionButton extends StatelessWidget {
  const _ComposerActionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(36),
        maximumSize: const Size.square(36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _ComposerSendButton extends StatelessWidget {
  const _ComposerSendButton({required this.isSending, required this.onPressed});

  final bool isSending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: isSending
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send_rounded, size: 18),
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.title,
    required this.conversation,
    required this.trust,
    required this.brandLabel,
    required this.onBack,
    required this.onOpenDetails,
    required this.onVerify,
    required this.transferCount,
  });

  final String title;
  final Conversation conversation;
  final ConversationKeyTrust? trust;
  final String? brandLabel;
  final VoidCallback onBack;
  final VoidCallback onOpenDetails;
  final Future<void> Function()? onVerify;
  final int transferCount;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return Container(
      padding: EdgeInsets.fromLTRB(
        spacing.xs,
        spacing.xs,
        spacing.md,
        spacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.appColors.background,
        border: Border(bottom: BorderSide(color: context.appColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip: 'Back',
          ),
          InkWell(
            onTap: onOpenDetails,
            borderRadius: BorderRadius.circular(context.appRadii.pill),
            child: AppAvatar(
              label: title,
              icon: conversation.isGroup ? Icons.forum_outlined : null,
              radius: 20,
            ),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: InkWell(
              onTap: onOpenDetails,
              borderRadius: BorderRadius.circular(context.appRadii.sm),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: spacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _headerSubtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.appColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (transferCount > 0)
            Icon(
              Icons.sync_rounded,
              size: 18,
              color: context.appColors.textMuted,
            ),
          if (onVerify != null)
            IconButton(
              onPressed: onVerify,
              icon: Icon(
                trust?.isEnterpriseVerified == true
                    ? Icons.verified_user_rounded
                    : Icons.shield_outlined,
              ),
            ),
        ],
      ),
    );
  }

  String _headerSubtitle() {
    final base = conversation.isGroup
        ? 'Workspace group'
        : 'Private conversation';
    if (brandLabel?.isNotEmpty == true) {
      return '$base • $brandLabel';
    }
    return base;
  }
}

class _ConversationProfilePage extends StatelessWidget {
  const _ConversationProfilePage({
    required this.title,
    required this.conversation,
    required this.trust,
  });

  final String title;
  final Conversation conversation;
  final ConversationKeyTrust? trust;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final isGroup = conversation.isGroup;
    final securityLabel = trust == null
        ? (isGroup ? 'Protected group conversation' : 'Security unavailable')
        : trust!.isEnterpriseVerified
        ? 'Verified security'
        : trust!.isEnterpriseReady
        ? 'Secure channel ready'
        : trust!.isVerified
        ? 'Verified device key'
        : 'Key verification pending';
    return AppScaffold(
      appBar: AppBar(title: Text(isGroup ? 'Group info' : 'Contact details')),
      body: ListView(
        padding: EdgeInsets.all(spacing.lg),
        children: [
          AppSurfaceCard(
            backgroundColor: colors.primarySoft,
            child: Column(
              children: [
                AppAvatar(
                  label: title,
                  icon: isGroup ? Icons.forum_outlined : null,
                  radius: 46,
                ),
                SizedBox(height: spacing.md),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                SizedBox(height: spacing.xs),
                Text(
                  isGroup ? 'Workspace group' : 'Private conversation',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.lg),
          AppSectionHeader(
            title: 'Conversation',
            subtitle: isGroup
                ? 'Shared messages are protected for the group.'
                : 'Messages are protected end-to-end.',
          ),
          SizedBox(height: spacing.sm),
          AppSurfaceCard(
            child: Column(
              children: [
                _ProfileInfoRow(
                  icon: Icons.lock_outline_rounded,
                  title: 'Security',
                  value: securityLabel,
                ),
                Divider(color: colors.border, height: spacing.lg),
                _ProfileInfoRow(
                  icon: Icons.photo_library_outlined,
                  title: 'Media',
                  value: 'Photos and files remain in this chat',
                ),
                Divider(color: colors.border, height: spacing.lg),
                _ProfileInfoRow(
                  icon: isGroup
                      ? Icons.groups_2_outlined
                      : Icons.person_outline_rounded,
                  title: isGroup ? 'Type' : 'Privacy',
                  value: isGroup
                      ? 'Group conversation'
                      : 'Private conversation',
                ),
              ],
            ),
          ),
          if (trust != null && !isGroup) ...[
            SizedBox(height: spacing.lg),
            const AppSectionHeader(
              title: 'Key status',
              subtitle: 'This device uses the current protected keyset.',
            ),
            SizedBox(height: spacing.sm),
            AppStatusBanner(
              message: securityLabel,
              tone: trust!.isEnterpriseVerified || trust!.isVerified
                  ? AppStatusTone.success
                  : AppStatusTone.info,
            ),
          ],
          SizedBox(height: spacing.lg),
          AppPrimaryButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Open chat'),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.appColors.primary),
        SizedBox(width: context.appSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: context.appSpacing.xs),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({
    required this.trust,
    required this.onVerify,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  final ConversationKeyTrust trust;
  final Future<void> Function() onVerify;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final summary = !trust.isAvailable
        ? 'Peer device key hali tayyor emas.'
        : trust.hasEnterpriseKeyChanged
        ? 'Security material changed. Re-verify recommended.'
        : trust.isEnterpriseVerified
        ? 'Enterprise trust verified.'
        : trust.isEnterpriseReady
        ? 'PQC ready. First secure send can proceed.'
        : trust.isVerified
        ? 'Classical trust verified.'
        : 'Key not verified yet.';

    final tone = !trust.isAvailable
        ? AppStatusTone.warning
        : trust.hasEnterpriseKeyChanged
        ? AppStatusTone.warning
        : trust.isEnterpriseVerified
        ? AppStatusTone.success
        : trust.isEnterpriseReady
        ? AppStatusTone.info
        : trust.isVerified
        ? AppStatusTone.success
        : AppStatusTone.info;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.appSpacing.sm,
        context.appSpacing.xs,
        context.appSpacing.sm,
        0,
      ),
      child: AppStatusBanner(
        message: summary,
        tone: tone,
        action: trust.isAvailable
            ? Wrap(
                spacing: context.appSpacing.xs,
                children: [
                  TextButton(
                    onPressed: onVerify,
                    child: Text(
                      trust.isEnterpriseVerified || trust.isVerified
                          ? 'Re-verify'
                          : 'Verify',
                    ),
                  ),
                  TextButton(
                    onPressed: onToggleExpanded,
                    child: Text(isExpanded ? 'Hide details' : 'Details'),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _SecurityDetailCard extends StatelessWidget {
  const _SecurityDetailCard({required this.trust});

  final ConversationKeyTrust trust;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final rows = <(String, String)>[
      ('X25519', trust.fingerprint ?? '-'),
      ('PQC-KEM', trust.pqcFingerprint ?? '-'),
      ('ML-DSA', trust.signingFingerprint ?? '-'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.sm, spacing.xs, spacing.sm, 0),
      child: AppSurfaceCard(
        padding: EdgeInsets.all(spacing.md),
        backgroundColor: context.appColors.surfaceMuted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Security details',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: spacing.sm),
            ...rows.map(
              (row) => Padding(
                padding: EdgeInsets.only(bottom: spacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        row.$1,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
