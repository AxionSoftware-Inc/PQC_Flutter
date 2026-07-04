import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/network/api_client.dart';
import '../../crypto/chat_crypto_exceptions.dart';
import '../data/chat_repository.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadMessages(showLoader: false),
    );
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) {
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
      );
      _messageController.clear();
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
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
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
              child: Row(
                children: [
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
            ),
          ),
        ],
      ),
    );
  }
}
