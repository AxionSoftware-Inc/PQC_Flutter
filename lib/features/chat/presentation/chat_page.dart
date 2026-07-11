import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/models/attachment.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/network/api_client.dart';
import '../../crypto/chat_crypto_exceptions.dart';
import '../data/chat_repository.dart';
import '../../security/key_verification_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.currentUserId,
    required this.conversation,
    required this.title,
    required this.chatRepository,
    required this.onUnauthorized,
  });

  final int currentUserId;
  final Conversation conversation;
  final String title;
  final ChatRepository chatRepository;
  final Future<void> Function() onUnauthorized;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = const [];
  Timer? _pollingTimer;
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  ConversationKeyTrust? _conversationTrust;
  List<_SelectedAttachment> _selectedAttachments = const [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadConversationTrust();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadMessages(showLoader: false);
      _loadConversationTrust();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final messages = await widget.chatRepository.fetchMessages(
        conversation: widget.conversation,
        currentUserId: widget.currentUserId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = messages;
        _error = null;
      });
      _jumpToBottom();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted && showLoader) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadConversationTrust() async {
    if (widget.conversation.isGroup) {
      return;
    }

    try {
      final trust = await widget.chatRepository.getConversationTrust(
        currentUserId: widget.currentUserId,
        conversation: widget.conversation,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _conversationTrust = trust;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _conversationTrust = null;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _selectedAttachments.isEmpty) || _isSending) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await widget.chatRepository.sendMessage(
        widget.conversation,
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
      );
      _messageController.clear();
      setState(() {
        _selectedAttachments = const [];
      });
      await _loadMessages(showLoader: false);
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
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
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
    await widget.chatRepository.retryMessage(
      conversation: widget.conversation,
      currentUserId: widget.currentUserId,
      clientMessageId: message.clientMessageId,
    );
    await _loadMessages(showLoader: false);
  }

  Future<void> _verifyCurrentKey() async {
    await widget.chatRepository.verifyConversationPeerKey(
      currentUserId: widget.currentUserId,
      conversation: widget.conversation,
    );
    await _loadConversationTrust();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Current key verified.')));
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (!widget.conversation.isGroup &&
              _conversationTrust?.isAvailable == true)
            IconButton(
              onPressed: _verifyCurrentKey,
              icon: Icon(
                _conversationTrust?.isVerified == true
                    ? Icons.verified_user
                    : Icons.shield_outlined,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          if (!widget.conversation.isGroup && _conversationTrust != null)
            _SecurityBanner(
              trust: _conversationTrust!,
              onVerify: _verifyCurrentKey,
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMine = message.senderId == widget.currentUserId;
                return Align(
                  alignment: isMine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    padding: const EdgeInsets.all(10),
                    color: isMine
                        ? Colors.blueGrey.shade100
                        : Colors.grey.shade200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.senderName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(message.body),
                        if (message.attachments.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: message.attachments
                                .map(_buildAttachmentChip)
                                .toList(),
                          ),
                        ],
                        if (message.deliveryState !=
                            MessageDeliveryState.sent) ...[
                          const SizedBox(height: 6),
                          Text(
                            _statusLabel(message),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (message.canRetry) ...[
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () => _retryMessage(message),
                            child: const Text('Retry'),
                          ),
                        ],
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
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (_selectedAttachments.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
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
                    const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _isSending ? null : _pickAttachments,
                        icon: const Icon(Icons.attach_file),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Message',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _isSending ? null : _sendMessage,
                        child: const Text('Send'),
                      ),
                    ],
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

    final backgroundColor = !trust.isAvailable
        ? Colors.grey.shade200
        : trust.hasEnterpriseKeyChanged
        ? Colors.orange.shade100
        : trust.isEnterpriseVerified
        ? Colors.teal.shade100
        : trust.isEnterpriseReady
        ? Colors.cyan.shade100
        : trust.isVerified
        ? Colors.green.shade100
        : Colors.blueGrey.shade100;

    return Container(
      width: double.infinity,
      color: backgroundColor,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          if (trust.isAvailable)
            TextButton(
              onPressed: onVerify,
              child: Text(
                trust.isEnterpriseVerified || trust.isVerified
                    ? 'Re-verify'
                    : 'Verify',
              ),
            ),
        ],
      ),
    );
  }
}
