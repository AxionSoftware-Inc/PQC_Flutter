import 'package:flutter/material.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/conversation.dart';
import '../../../core/network/api_client.dart';
import '../../auth/session_controller.dart';
import '../data/chat_repository.dart';
import 'chat_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({
    super.key,
    required this.sessionController,
    required this.chatRepository,
  });

  final SessionController sessionController;
  final ChatRepository chatRepository;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  bool _isLoading = true;
  String? _error;
  List<AppUser> _users = const [];
  List<Conversation> _conversations = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final users = await widget.chatRepository.fetchUsers();
      final conversations = await widget.chatRepository.fetchConversations(
        currentUserId: widget.sessionController.sessionUser!.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _users = users;
        _conversations = conversations;
      });
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.sessionController.invalidateSession();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openGroupChat(Conversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          currentUserId: widget.sessionController.sessionUser!.id,
          conversation: conversation,
          title: conversation.title,
          chatRepository: widget.chatRepository,
          onUnauthorized: widget.sessionController.invalidateSession,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openPrivateChat(AppUser user) async {
    try {
      final conversation = await widget.chatRepository.openPrivateConversation(
        user.id,
      );
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            currentUserId: widget.sessionController.sessionUser!.id,
            conversation: conversation,
            title: user.displayName,
            chatRepository: widget.chatRepository,
            onUnauthorized: widget.sessionController.invalidateSession,
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.sessionController.invalidateSession();
        return;
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionUser = widget.sessionController.sessionUser!;
    Conversation? groupConversation;
    for (final conversation in _conversations) {
      if (conversation.isGroup) {
        groupConversation = conversation;
        break;
      }
    }
    final privateConversations = {
      for (final conversation in _conversations.where((item) => !item.isGroup))
        conversation.participantIds.firstWhere(
          (id) => id != sessionUser.id,
          orElse: () => -1,
        ): conversation,
    };
    final otherUsers = _users
        .where((user) => user.id != sessionUser.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Chats - ${sessionUser.username}'),
        actions: [
          IconButton(
            onPressed: widget.sessionController.logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isLoading) const LinearProgressIndicator(),
            if (_error != null) ...[Text(_error!), const SizedBox(height: 12)],
            const Text('Group chat'),
            const SizedBox(height: 8),
            if (groupConversation != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(groupConversation.title),
                subtitle: Text(
                  groupConversation.lastMessagePreview.isEmpty
                      ? 'Open group chat'
                      : groupConversation.lastMessagePreview,
                ),
                onTap: () => _openGroupChat(groupConversation!),
              )
            else
              const Text('No group conversation found.'),
            const Divider(),
            const Text('Private chats'),
            const SizedBox(height: 8),
            for (final user in otherUsers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(user.displayName),
                subtitle: Text(
                  privateConversations[user.id]
                              ?.lastMessagePreview
                              .isNotEmpty ==
                          true
                      ? privateConversations[user.id]!.lastMessagePreview
                      : user.hasUsableDeviceKey
                      ? 'Start private chat'
                      : 'Device key tayyor emas. U avval ilovaga kirishi kerak.',
                ),
                onTap: () => _openPrivateChat(user),
              ),
          ],
        ),
      ),
    );
  }
}
