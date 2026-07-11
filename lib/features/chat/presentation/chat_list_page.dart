import 'package:flutter/material.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/organization_context.dart';
import '../../../core/models/session_user.dart';
import '../../../core/network/api_client.dart';
import '../../auth/session_controller.dart';
import '../../security/key_verification_service.dart';
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
  int _selectedTabIndex = 0;
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
    final theme = Theme.of(context);
    final sessionUser = widget.sessionController.sessionUser!;
    final currentWorkspace = _currentWorkspace(sessionUser);
    final allUsersSorted = [..._users]
      ..sort((a, b) {
        if (a.id == sessionUser.id) {
          return -1;
        }
        if (b.id == sessionUser.id) {
          return 1;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    final conversations = [..._conversations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final groupConversation = conversations
        .where((item) => item.isGroup)
        .firstOrNull;
    final privateConversations = {
      for (final conversation in conversations.where((item) => !item.isGroup))
        conversation.participantIds.firstWhere(
          (id) => id != sessionUser.id,
          orElse: () => -1,
        ): conversation,
    };
    final currentUser = allUsersSorted
        .where((user) => user.id == sessionUser.id)
        .firstOrNull;

    final tabs = [
      _TabMeta(
        label: 'Chats',
        icon: Icons.chat_bubble_outline_rounded,
        title: currentWorkspace?.name ?? 'Chats',
      ),
      const _TabMeta(
        label: 'Contacts',
        icon: Icons.people_alt_outlined,
        title: 'Contacts',
      ),
      const _TabMeta(
        label: 'Settings',
        icon: Icons.settings_outlined,
        title: 'Settings',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tabs[_selectedTabIndex].title),
            Text(sessionUser.displayName, style: theme.textTheme.labelMedium),
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
              icon: const Icon(Icons.apartment_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isLoading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _selectedTabIndex,
                children: [
                  RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (conversations.isEmpty)
                          _buildEmptyCard(
                            'Hali chatlar yo\'q. Contacts tabidan user tanlab private chat ochishingiz mumkin.',
                          ),
                        if (groupConversation != null)
                          _buildConversationTile(
                            title: groupConversation.title,
                            preview:
                                groupConversation.lastMessagePreview.isEmpty
                                ? 'Open shared workspace chat'
                                : groupConversation.lastMessagePreview,
                            icon: Icons.forum_outlined,
                            onTap: () => _openGroupChat(groupConversation),
                          )
                        else if (conversations.isEmpty)
                          _buildEmptyCard(
                            'Hali group chat topilmadi. Backendda workspace group conversation yaratilgach shu yerda chiqadi.',
                          ),
                        for (final conversation in conversations.where(
                          (item) => !item.isGroup,
                        ))
                          _buildConversationTile(
                            title: _conversationTitle(
                              conversation: conversation,
                              currentUserId: sessionUser.id,
                            ),
                            preview: conversation.lastMessagePreview.isEmpty
                                ? 'Open private chat'
                                : conversation.lastMessagePreview,
                            icon: Icons.chat_bubble_outline_rounded,
                            onTap: () {
                              final peerId = conversation.participantIds
                                  .firstWhere(
                                    (id) => id != sessionUser.id,
                                    orElse: () => -1,
                                  );
                              final peerUser = _users
                                  .where((user) => user.id == peerId)
                                  .firstOrNull;
                              if (peerUser == null) {
                                return;
                              }
                              _openPrivateChat(peerUser);
                            },
                          ),
                      ],
                    ),
                  ),
                  RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildContactsHeader(
                          context: context,
                          totalUsers: allUsersSorted.length,
                          readyUsers: _users
                              .where((user) => user.hasUsablePqcDeviceKey)
                              .length,
                        ),
                        const SizedBox(height: 16),
                        for (final user in allUsersSorted)
                          _buildContactTile(
                            sessionUser: sessionUser,
                            user: user,
                            privateConversation: privateConversations[user.id],
                          ),
                      ],
                    ),
                  ),
                  RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildSettingsCard(
                          context: context,
                          sessionUser: sessionUser,
                          currentWorkspace: currentWorkspace,
                        ),
                        const SizedBox(height: 16),
                        Text('My devices', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        if (currentUser != null &&
                            currentUser.devices.isNotEmpty)
                          for (final device in currentUser.devices)
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.devices_outlined),
                                ),
                                title: Text(
                                  device.deviceName.isEmpty
                                      ? device.deviceId
                                      : device.deviceName,
                                ),
                                subtitle: Text(
                                  '${device.platform.isEmpty ? 'unknown' : device.platform} • ${device.hasUsableMlKemKey && device.hasUsableMlDsaKey ? 'PQC ready' : 'PQC not ready'}',
                                ),
                              ),
                            )
                        else
                          _buildEmptyCard('No registered devices yet.'),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: widget.sessionController.logout,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Logout'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        destinations: [
          for (final tab in tabs)
            NavigationDestination(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }

  Widget _buildConversationTile({
    required String title,
    required String preview,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }

  Widget _buildContactTile({
    required SessionUser sessionUser,
    required AppUser user,
    required Conversation? privateConversation,
  }) {
    final isSelf = user.id == sessionUser.id;
    final trust = _trustByUserId[user.id];
    final subtitle = isSelf
        ? 'This device account'
        : user.hasUsablePqcDeviceKey
        ? trust?.isEnterpriseVerified == true
              ? 'PQC ready and verified'
              : 'PQC ready'
        : 'PQC key not ready yet';

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase(),
          ),
        ),
        title: Text(isSelf ? '${user.displayName} (You)' : user.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(subtitle),
            Text(
              '${user.devices.length} device${user.devices.length == 1 ? '' : 's'}${privateConversation != null ? ' • DM ready' : ''}',
            ),
          ],
        ),
        trailing: isSelf
            ? const Icon(Icons.person)
            : const Icon(Icons.chat_bubble_outline_rounded),
        onTap: isSelf ? null : () => _openPrivateChat(user),
      ),
    );
  }

  Widget _buildContactsHeader({
    required BuildContext context,
    required int totalUsers,
    required int readyUsers,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            child: Icon(Icons.people_alt_outlined),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Workspace directory', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Bu yerda saqlanganlar emas, bazadagi barcha mavjud userlar ko\'rinadi.',
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$totalUsers', style: theme.textTheme.titleLarge),
              Text('$readyUsers PQC ready'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({
    required BuildContext context,
    required SessionUser sessionUser,
    required WorkspaceSummary? currentWorkspace,
  }) {
    final theme = Theme.of(context);
    final organizations = sessionUser.organizations.length;
    final workspaces = sessionUser.organizations.fold<int>(
      0,
      (sum, item) => sum + item.workspaces.length,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.tertiaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Profile and workspace', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          _buildInfoRow('Display name', sessionUser.displayName),
          _buildInfoRow('Username', sessionUser.username),
          _buildInfoRow('Workspace', currentWorkspace?.name ?? 'Not selected'),
          _buildInfoRow('Workspace ID', '${sessionUser.activeWorkspaceId}'),
          _buildInfoRow('Organizations', '$organizations'),
          _buildInfoRow('Available workspaces', '$workspaces'),
          _buildInfoRow('Device ID', sessionUser.deviceId),
        ],
      ),
    );
  }

  String _conversationTitle({
    required Conversation conversation,
    required int currentUserId,
  }) {
    if (conversation.isGroup) {
      return conversation.title;
    }
    final peerId = conversation.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => -1,
    );
    final peerUser = _users.where((user) => user.id == peerId).firstOrNull;
    return peerUser?.displayName ?? conversation.title;
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String text) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
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

class _TabMeta {
  const _TabMeta({
    required this.label,
    required this.icon,
    required this.title,
  });

  final String label;
  final IconData icon;
  final String title;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) {
      return null;
    }
    return first;
  }
}
