import 'package:flutter/material.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/organization_context.dart';
import '../../../core/models/session_user.dart';
import '../../../core/network/api_client.dart';
import '../../auth/session_controller.dart';
import '../data/chat_repository.dart';
import '../../security/key_verification_service.dart';
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
  Map<int, UserKeyTrust> _trustByUserId = const {};

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
      final trustByUserId = await widget.chatRepository.buildUserTrustMap();
      if (!mounted) {
        return;
      }
      setState(() {
        _users = users;
        _conversations = conversations;
        _trustByUserId = trustByUserId;
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

  Future<void> _switchWorkspace(int workspaceId) async {
    await widget.sessionController.switchWorkspace(workspaceId);
    if (!mounted) {
      return;
    }
    await _load();
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
    final currentUserEntry = _users.where((user) => user.id == sessionUser.id);
    final currentUser = currentUserEntry.isEmpty
        ? null
        : currentUserEntry.first;
    final currentWorkspace = _currentWorkspace(sessionUser);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chats - ${sessionUser.displayName}'),
            if (currentWorkspace != null)
              Text(
                currentWorkspace.name,
                style: Theme.of(context).textTheme.labelMedium,
              ),
          ],
        ),
        actions: [
          if (sessionUser.organizations.isNotEmpty)
            PopupMenuButton<int>(
              tooltip: 'Switch workspace',
              onSelected: _switchWorkspace,
              itemBuilder: (context) {
                final items = <PopupMenuEntry<int>>[];
                for (final organization in sessionUser.organizations) {
                  items.add(
                    PopupMenuItem<int>(
                      enabled: false,
                      child: Text(organization.name),
                    ),
                  );
                  for (final workspace in organization.workspaces) {
                    items.add(
                      PopupMenuItem<int>(
                        value: workspace.id,
                        child: Row(
                          children: [
                            Expanded(child: Text(workspace.name)),
                            if (workspace.id == sessionUser.activeWorkspaceId)
                              const Icon(Icons.check, size: 18),
                          ],
                        ),
                      ),
                    );
                  }
                }
                return items;
              },
              icon: const Icon(Icons.business_outlined),
            ),
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
            const Text('My devices'),
            const SizedBox(height: 8),
            if (currentUser != null && currentUser.devices.isNotEmpty)
              for (final device in currentUser.devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices_outlined),
                  title: Text(
                    device.deviceName.isEmpty
                        ? device.deviceId
                        : device.deviceName,
                  ),
                  subtitle: Text(
                    '${device.platform.isEmpty ? 'unknown' : device.platform} • ${device.hasUsableMlKemKey && device.hasUsableMlDsaKey ? 'PQC ready' : 'PQC not ready'}',
                  ),
                )
            else
              const Text('No registered devices yet.'),
            const Divider(),
            const Text('Private chats'),
            const SizedBox(height: 8),
            if (otherUsers.isEmpty)
              const Text(
                'No other workspace users yet. Open the app on your phone/tablet or log in with another account to test private chat.',
              ),
            for (final user in otherUsers)
              _buildPrivateUserTile(
                user: user,
                privateConversation: privateConversations[user.id],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivateUserTile({
    required AppUser user,
    required Conversation? privateConversation,
  }) {
    final trust = _trustByUserId[user.id];
    final subtitle = privateConversation?.lastMessagePreview.isNotEmpty == true
        ? privateConversation!.lastMessagePreview
        : trust?.hasAnyKeyChanged == true
        ? 'Security material changed. Re-verify before trusting.'
        : user.hasUsablePqcDeviceKey
        ? trust?.isEnterpriseVerified == true
              ? 'Enterprise-ready PQC trust verified'
              : 'PQC ready. Verification needed.'
        : 'PQC key not ready yet. Reopen that device once.';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(user.displayName),
      subtitle: Text(subtitle),
      trailing: trust?.hasAnyKeyChanged == true
          ? const Icon(Icons.warning_amber_rounded, color: Colors.orange)
          : trust?.isEnterpriseVerified == true
          ? const Icon(Icons.verified, color: Colors.teal)
          : trust?.isVerified == true
          ? const Icon(Icons.verified_user, color: Colors.green)
          : null,
      onTap: () => _openPrivateChat(user),
    );
  }

  WorkspaceSummary? _currentWorkspace(SessionUser sessionUser) {
    for (final organization in sessionUser.organizations) {
      for (final workspace in organization.workspaces) {
        if (workspace.id == sessionUser.activeWorkspaceId) {
          return workspace;
        }
      }
    }
    return null;
  }
}
