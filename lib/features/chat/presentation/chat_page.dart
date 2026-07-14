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
import '../application/chat_controllers.dart';
import '../application/chat_facade.dart';
import '../application/chat_models.dart';
import '../application/chat_services.dart';
import '../../transfers/application/attachment_transfer.dart';
import 'chat_page_widgets.dart';
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
  ChatMessage? _replyingTo;
  final Map<int, String> _localReactions = <int, String>{};
  int _lastMessageCount = 0;
  bool _hasRenderedMessages = false;
  final Map<int, String> _downloadedAttachmentPaths = {};

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
    for (final transfer in _controller.attachmentTransfers) {
      if (transfer.attachmentId != null && transfer.localPath != null) {
        _downloadedAttachmentPaths[transfer.attachmentId!] =
            transfer.localPath!;
      }
    }
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
          ChatConversationHeader(
            title: widget.title,
            conversation: widget.conversation,
            trust: conversationTrust,
            brandLabel: brand?.label,
            onBack: () => Navigator.of(context).maybePop(),
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
                ChatSecurityBanner(
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
                  ChatSecurityDetailCard(trust: conversationTrust),
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
                      final previous = index == 0
                          ? null
                          : _controller.messages[index - 1];
                      final showDate =
                          previous == null ||
                          !_isSameCalendarDay(
                            previous.createdAt,
                            message.createdAt,
                          );
                      final grouped =
                          previous != null &&
                          previous.senderId == message.senderId &&
                          _isSameCalendarDay(
                            previous.createdAt,
                            message.createdAt,
                          ) &&
                          message.createdAt
                                  .difference(previous.createdAt)
                                  .inMinutes <=
                              5;
                      return Column(
                        children: [
                          if (showDate) _buildDateSeparator(message.createdAt),
                          _buildMessageItem(
                            message: message,
                            isMine: isMine,
                            isGrouped: grouped,
                          ),
                        ],
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
                  if (_replyingTo != null) _buildReplyPreview(),
                  AppSurfaceCard(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.xs,
                      vertical: spacing.xs,
                    ),
                    backgroundColor: colors.surface.withValues(alpha: 0.96),
                    child: Row(
                      children: [
                        ChatComposerActionButton(
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
                        ChatComposerSendButton(
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
    bool isGrouped = false,
  }) {
    return ChatMessageBubble(
      message: message,
      isMine: isMine,
      isGrouped: isGrouped,
      reaction: _localReactions[message.id],
      maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      attachmentBuilder: _buildAttachmentCard,
      statusLabel: _statusLabel,
      formatTime: _formatMessageTime,
      onRetry: () => _retryMessage(message),
      onLongPress: () => _showMessageActions(message),
    );
  }

  Widget _buildReplyPreview() {
    final message = _replyingTo!;
    return Padding(
      padding: EdgeInsets.only(bottom: context.appSpacing.xs),
      child: AppSurfaceCard(
        backgroundColor: context.appColors.primarySoft,
        padding: EdgeInsets.symmetric(
          horizontal: context.appSpacing.sm,
          vertical: context.appSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              Icons.reply_rounded,
              size: 18,
              color: context.appColors.primary,
            ),
            SizedBox(width: context.appSpacing.xs),
            Expanded(
              child: Text(
                'Replying to ${message.senderName}: ${message.body.isEmpty ? 'Attachment' : message.body}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _replyingTo = null),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(sheetContext, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: const Text('React'),
              onTap: () => Navigator.pop(sheetContext, 'react'),
            ),
            ListTile(
              leading: const Icon(Icons.forward_rounded),
              title: const Text('Forward'),
              onTap: () => Navigator.pop(sheetContext, 'forward'),
            ),
            if (message.senderId == widget.currentUserId) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete'),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'reply':
        setState(() => _replyingTo = message);
      case 'react':
        await _chooseReaction(message);
      case 'forward':
      case 'edit':
      case 'delete':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$action will be connected to the server contract.'),
          ),
        );
    }
  }

  Future<void> _chooseReaction(ChatMessage message) async {
    final reaction = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          context.appSpacing.lg,
          context.appSpacing.sm,
          context.appSpacing.lg,
          context.appSpacing.lg,
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: context.appSpacing.md,
          children: ['👍', '❤️', '😂', '😮', '😢', '👏']
              .map(
                (emoji) => IconButton(
                  iconSize: 30,
                  onPressed: () => Navigator.pop(sheetContext, emoji),
                  icon: Text(emoji),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (reaction != null && mounted) {
      setState(() => _localReactions[message.id] = reaction);
    }
  }

  Widget _buildDateSeparator(DateTime value) {
    final local = value.toLocal();
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final label = _isSameCalendarDay(local, today)
        ? 'Today'
        : _isSameCalendarDay(local, yesterday)
        ? 'Yesterday'
        : '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.appSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.surfaceMuted,
          borderRadius: BorderRadius.circular(context.appRadii.pill),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.appSpacing.sm,
            vertical: context.appSpacing.xs,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.appColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  bool _isSameCalendarDay(DateTime first, DateTime second) {
    final a = first.toLocal();
    final b = second.toLocal();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildAttachmentCard(ChatAttachment attachment) {
    return ChatAttachmentCard(
      attachment: attachment,
      transfer: _controller.findDownloadTransfer(attachment.id),
      localPath: _downloadedAttachmentPaths[attachment.id],
      formatBytes: _formatBytes,
      statusLabel: _transferStatusLabel,
      onPressed: () => _handleAttachmentTap(attachment),
    );
  }

  Future<void> _handleAttachmentTap(ChatAttachment attachment) async {
    final transfer = _controller.findDownloadTransfer(attachment.id);
    final isBusy =
        transfer != null &&
        transfer.status != AttachmentTransferStatus.completed &&
        transfer.status != AttachmentTransferStatus.failed;
    if (isBusy) {
      await _controller.pauseTransfer(transfer.localId);
      return;
    }

    final existingPath = _downloadedAttachmentPaths[attachment.id];
    if (existingPath != null && attachment.mimeType.startsWith('image/')) {
      await _showImageLightbox(attachment.filename, existingPath);
      return;
    }
    try {
      final path =
          existingPath ?? await _controller.downloadAttachment(attachment);
      if (!mounted) {
        return;
      }
      _downloadedAttachmentPaths[attachment.id] = path;
      setState(() {});
      if (attachment.mimeType.startsWith('image/')) {
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
      if (!mounted || result.type == ResultType.done) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isEmpty
                ? 'Downloaded, but no app can open this file.'
                : result.message,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showImageLightbox(String title, String path) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.82,
              width: double.infinity,
              child: buildChatLocalImageViewer(dialogContext, path),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded),
                tooltip: title,
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
    final activeTransfers = _controller.attachmentTransfers
        .where((item) => item.status != AttachmentTransferStatus.completed)
        .toList();
    final aggregateProgress = activeTransfers.isEmpty
        ? 1.0
        : activeTransfers
                  .map((item) => item.progress.fraction.clamp(0, 1).toDouble())
                  .fold<double>(0, (sum, value) => sum + value) /
              activeTransfers.length;
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
                        if (activeCount > 0) ...[
                          SizedBox(height: spacing.xs),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              context.appRadii.sm,
                            ),
                            child: LinearProgressIndicator(
                              value: aggregateProgress,
                              minHeight: 3,
                            ),
                          ),
                        ],
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
            ...List<AttachmentTransferState>.of(
              _controller.attachmentTransfers,
            ).map(
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
              if (!isTerminal) ...[
                SizedBox(width: spacing.xs),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
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
