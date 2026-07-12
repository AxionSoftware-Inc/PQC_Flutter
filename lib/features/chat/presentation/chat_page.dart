import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
    setState(() {});
    _jumpToBottom();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _selectedAttachments.isEmpty) || _controller.isSending) {
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
      withData: true,
    );
    if (result == null || !mounted) {
      return;
    }
    final picked = result.files
        .where((file) => file.bytes != null)
        .map(
          (file) => _SelectedAttachment(
            name: file.name,
            bytes: file.bytes!,
            mimeType: _inferMimeType(file.name),
          ),
        )
        .toList();
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
            onVerify: !widget.conversation.isGroup &&
                    conversationTrust?.isAvailable == true
                ? _verifyCurrentKey
                : null,
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
            _SecurityBanner(
              trust: conversationTrust,
              onVerify: _verifyCurrentKey,
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
                        message: 'Conversation hali bo‘sh. Birinchi xabarni yuboring.',
                        icon: Icons.chat_bubble_outline_rounded,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
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
              padding: EdgeInsets.all(spacing.md),
              child: Column(
                children: [
                  if (_selectedAttachments.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: spacing.sm,
                        runSpacing: spacing.sm,
                        children: _selectedAttachments
                            .map(
                              (item) => InputChip(
                                avatar: Icon(
                                  item.isImage
                                      ? Icons.image_outlined
                                      : Icons.attach_file,
                                  size: 18,
                                ),
                                label: Text(
                                  '${item.name} (${_formatBytes(item.bytes.length)})',
                                ),
                                onDeleted: () =>
                                    _removeSelectedAttachment(item),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (_selectedAttachments.isNotEmpty)
                    SizedBox(height: spacing.sm),
                  AppSurfaceCard(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.sm,
                      vertical: spacing.sm,
                    ),
                    backgroundColor: colors.surface.withValues(alpha: 0.96),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed:
                              _controller.isSending ? null : _pickAttachments,
                          icon: const Icon(Icons.attach_file),
                        ),
                        Expanded(
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              inputDecorationTheme:
                                  Theme.of(context).inputDecorationTheme.copyWith(
                                    filled: false,
                                    fillColor: Colors.transparent,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: spacing.md,
                                      vertical: spacing.sm,
                                    ),
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    border: InputBorder.none,
                                  ),
                            ),
                            child: AppTextField(
                              controller: _messageController,
                              hintText: 'iMessage',
                              maxLines: 5,
                              minLines: 1,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        SizedBox(width: spacing.sm),
                        SizedBox(
                          height: 40,
                          child: AppPrimaryButton(
                          onPressed:
                              _controller.isSending ? null : _sendMessage,
                          label: Text(
                            _controller.isSending ? 'Sending...' : 'Send',
                          ),
                        ),
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
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: EdgeInsets.symmetric(horizontal: spacing.md, vertical: spacing.xs),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(spacing.md),
              decoration: BoxDecoration(
                color: isMine ? colors.chatMine : colors.chatPeer,
                borderRadius: BorderRadius.circular(context.appRadii.md),
                border: Border.all(
                  color: isMine
                      ? colors.primary.withValues(alpha: 0.16)
                      : colors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.senderName,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.78)
                          : colors.textMuted,
                    ),
                  ),
                  SizedBox(height: spacing.xs),
                  if (isDecryptNeedsRestore)
                    Text(
                      'Historical decrypt unavailable on this device. Restore backup to read this message.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: isMine ? Colors.white : null,
                      ),
                    )
                  else if (isDecryptError)
                    Text(
                      'Unable to decrypt this message.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: isMine ? Colors.white : null,
                      ),
                    )
                  else
                    Text(
                      message.body,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: isMine ? Colors.white : null,
                      ),
                    ),
                  if (message.attachments.isNotEmpty) ...[
                    SizedBox(height: spacing.sm),
                    Wrap(
                      spacing: spacing.sm,
                      runSpacing: spacing.sm,
                      children: message.attachments.map(_buildAttachmentChip).toList(),
                    ),
                  ],
                  SizedBox(height: spacing.sm),
                  Wrap(
                    spacing: spacing.xs,
                    runSpacing: spacing.xs,
                    children: [
                      const AppBadge(
                        label: 'Encrypted',
                        tone: AppStatusTone.info,
                        icon: Icons.lock_outline_rounded,
                      ),
                      if (!widget.conversation.isGroup)
                        AppBadge(
                          label: _controller.trust?.trust.isEnterpriseVerified == true
                              ? 'Verified'
                              : 'Trust',
                          tone: _controller.trust?.trust.isEnterpriseVerified == true
                              ? AppStatusTone.success
                              : AppStatusTone.info,
                          icon: _controller.trust?.trust.isEnterpriseVerified == true
                              ? Icons.verified_user_rounded
                              : Icons.shield_outlined,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (message.deliveryState != MessageDeliveryState.sent)
              Padding(
                padding: EdgeInsets.only(top: spacing.xs),
                child: Text(
                  _statusLabel(message),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
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
    );
  }

  Widget _buildAttachmentChip(ChatAttachment attachment) {
    return Chip(
      avatar: Icon(
        attachment.mimeType.startsWith('image/')
            ? Icons.image_outlined
            : Icons.insert_drive_file_outlined,
        size: 18,
      ),
      label: Text(
        '${attachment.filename} (${_formatBytes(attachment.sizeBytes)})',
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final List<int> bytes;
  final String mimeType;

  bool get isImage => mimeType.startsWith('image/');
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.title,
    required this.conversation,
    required this.trust,
    required this.brandLabel,
    required this.onVerify,
  });

  final String title;
  final Conversation conversation;
  final ConversationKeyTrust? trust;
  final String? brandLabel;
  final Future<void> Function()? onVerify;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.md, spacing.sm, spacing.md, 0),
      child: AppSurfaceCard(
        child: Row(
          children: [
            AppAvatar(
              label: title,
              icon: conversation.isGroup ? Icons.forum_outlined : null,
              radius: 22,
            ),
            SizedBox(width: spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  SizedBox(height: spacing.xs),
                  Text(
                    brandLabel?.isNotEmpty == true
                        ? '${conversation.isGroup ? 'Workspace group' : 'Private conversation'} • $brandLabel'
                        : (conversation.isGroup
                              ? 'Workspace group'
                              : 'Private conversation'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textMuted,
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  Wrap(
                    spacing: spacing.xs,
                    runSpacing: spacing.xs,
                    children: [
                      if (!conversation.isGroup && trust != null)
                        AppBadge(
                          label: trust!.isEnterpriseVerified
                              ? 'Verified'
                              : trust!.hasEnterpriseKeyChanged
                              ? 'Attention'
                              : trust!.isEnterpriseReady
                              ? 'Ready'
                              : 'Not ready',
                          tone: trust!.isEnterpriseVerified
                              ? AppStatusTone.success
                              : trust!.hasEnterpriseKeyChanged
                              ? AppStatusTone.warning
                              : trust!.isEnterpriseReady
                              ? AppStatusTone.info
                              : AppStatusTone.danger,
                        ),
                      AppBadge(
                        label: conversation.isGroup ? 'Multi-device' : 'Device trust',
                        tone: AppStatusTone.info,
                      ),
                    ],
                  ),
                ],
              ),
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
      ),
    );
  }
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.trust, required this.onVerify});

  final ConversationKeyTrust trust;
  final Future<void> Function() onVerify;

  @override
  Widget build(BuildContext context) {
    final text = !trust.isAvailable
        ? 'Peer device key hali tayyor emas.'
        : trust.hasEnterpriseKeyChanged
        ? 'Warning: peer security material changed. Re-verify. X25519: ${trust.fingerprint ?? '-'} PQC-KEM: ${trust.pqcFingerprint ?? '-'} ML-DSA: ${trust.signingFingerprint ?? '-'}'
        : trust.isEnterpriseVerified
        ? 'Enterprise trust verified. X25519: ${trust.fingerprint ?? '-'} PQC-KEM: ${trust.pqcFingerprint ?? '-'} ML-DSA: ${trust.signingFingerprint ?? '-'}'
        : trust.isEnterpriseReady
        ? 'PQC ready. Current device material will be trusted on first send. X25519: ${trust.fingerprint ?? '-'} PQC-KEM: ${trust.pqcFingerprint ?? '-'} ML-DSA: ${trust.signingFingerprint ?? '-'}'
        : trust.isVerified
        ? 'Classical trust verified. X25519: ${trust.fingerprint ?? '-'}'
        : 'Key not verified yet. X25519: ${trust.fingerprint ?? '-'}';

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
        context.appSpacing.sm,
        context.appSpacing.sm,
        0,
      ),
      child: AppStatusBanner(
        message: text,
        tone: tone,
        action: trust.isAvailable
            ? TextButton(
                onPressed: onVerify,
                child: Text(
                  trust.isEnterpriseVerified || trust.isVerified
                      ? 'Re-verify'
                      : 'Verify',
                ),
              )
            : null,
      ),
    );
  }
}
