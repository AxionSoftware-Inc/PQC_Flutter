import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/network/api_client.dart';
import '../../crypto/chat_crypto_exceptions.dart';
import '../../security/key_verification_service.dart';
import '../application/chat_controllers.dart';
import '../application/chat_facade.dart';
import '../application/chat_models.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.currentUserId,
    required this.conversation,
    required this.title,
    required this.chatFacade,
    required this.onUnauthorized,
  });

  final int currentUserId;
  final Conversation conversation;
  final String title;
  final ChatFacade chatFacade;
  final Future<void> Function() onUnauthorized;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final ChatConversationController _controller;
  List<_SelectedAttachment> _selectedAttachments = const [];

  @override
  void initState() {
    super.initState();
    _controller = ChatConversationController(
      chatFacade: widget.chatFacade,
      currentUserId: widget.currentUserId,
      conversation: widget.conversation,
    )..addListener(_onControllerChanged);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.onUnauthorized();
      }
    }
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
    return AppScaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 8,
        title: Row(
          children: [
            AppAvatar(
              label: widget.title,
              icon: widget.conversation.isGroup ? Icons.forum_outlined : null,
              radius: 18,
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (!widget.conversation.isGroup &&
              conversationTrust?.isAvailable == true)
            IconButton(
              onPressed: _verifyCurrentKey,
              icon: Icon(
                conversationTrust?.isVerified == true
                    ? Icons.verified_user
                    : Icons.shield_outlined,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
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
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _controller.messages.length,
              itemBuilder: (context, index) {
                final message = _controller.messages[index];
                final isMine = message.senderId == widget.currentUserId;
                return Align(
                  alignment: isMine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    margin: EdgeInsets.symmetric(
                      horizontal: spacing.md,
                      vertical: spacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(spacing.md),
                          decoration: BoxDecoration(
                            color: isMine ? colors.chatMine : colors.chatPeer,
                            borderRadius: BorderRadius.circular(
                              context.appRadii.md,
                            ),
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
                                  children: message.attachments
                                      .map(_buildAttachmentChip)
                                      .toList(),
                                ),
                              ],
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
        return 'Pending sync...';
      case MessageDeliveryState.failedRetryable:
        return message.failureReason ?? 'Send failed. Retry available.';
      case MessageDeliveryState.failedPermanent:
        return message.failureReason ?? 'Send failed permanently.';
      case MessageDeliveryState.sent:
        return '';
    }
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
