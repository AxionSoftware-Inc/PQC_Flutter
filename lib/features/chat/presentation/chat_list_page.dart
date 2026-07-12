import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/organization_context.dart';
import '../../../core/models/session_user.dart';
import '../../../core/network/api_client.dart';
import '../../auth/session_controller.dart';
import '../application/chat_controllers.dart';
import '../application/chat_facade.dart';
import 'chat_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({
    super.key,
    required this.sessionController,
    required this.chatFacade,
  });

  final SessionController sessionController;
  final ChatFacade chatFacade;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  late final ChatListController _controller;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = ChatListController(
      chatFacade: widget.chatFacade,
      currentUserId: widget.sessionController.sessionUser!.id,
    )..addListener(_onControllerChanged);
    _load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    try {
      await _controller.load();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.sessionController.invalidateSession();
        return;
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
          chatFacade: widget.chatFacade,
          onUnauthorized: widget.sessionController.invalidateSession,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openPrivateChat(AppUser user) async {
    try {
      final conversation = await _controller.openPrivateConversation(user.id);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            currentUserId: widget.sessionController.sessionUser!.id,
            conversation: conversation,
            title: user.displayName,
            chatFacade: widget.chatFacade,
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
    _controller.switchWorkspaceContext(workspaceId);
    if (!mounted) {
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final sessionUser = widget.sessionController.sessionUser!;
    final users = _controller.users;
    final conversationsState = _controller.conversations;
    final currentWorkspace = _currentWorkspace(sessionUser);
    final allUsersSorted = [...users]
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
    final conversations = [...conversationsState]
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

    return AppScaffold(
      appBar: AppBar(
        toolbarHeight: 74,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              tabs[_selectedTabIndex].title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: spacing.xs),
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
            if (_controller.isLoading) const LinearProgressIndicator(minHeight: 2),
            if (_controller.error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  spacing.md,
                  spacing.lg,
                  0,
                ),
                child: AppStatusBanner(
                  message: _controller.error!,
                  tone: AppStatusTone.danger,
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _selectedTabIndex,
                children: [
                  RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: EdgeInsets.all(spacing.lg),
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
                              final peerUser = users
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
                      padding: EdgeInsets.all(spacing.lg),
                      children: [
                        _buildContactsHeader(
                          context: context,
                          totalUsers: allUsersSorted.length,
                          readyUsers: users
                              .where((user) => user.hasUsablePqcDeviceKey)
                              .length,
                        ),
                        SizedBox(height: spacing.lg),
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
                      padding: EdgeInsets.all(spacing.lg),
                      children: [
                        _buildSettingsCard(
                          context: context,
                          sessionUser: sessionUser,
                          currentWorkspace: currentWorkspace,
                        ),
                        SizedBox(height: spacing.lg),
                        const AppSectionHeader(
                          title: 'My devices',
                          subtitle: 'Current profile and registered PQC-ready devices.',
                        ),
                        SizedBox(height: spacing.sm),
                        if (currentUser != null &&
                            currentUser.devices.isNotEmpty)
                          for (final device in currentUser.devices)
                            Padding(
                              padding: EdgeInsets.only(bottom: spacing.sm),
                              child: AppSurfaceCard(
                                onTap: () {},
                                child: Row(
                                  children: [
                                    const AppAvatar(
                                      label: 'D',
                                      icon: Icons.devices_outlined,
                                    ),
                                    SizedBox(width: spacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            device.deviceName.isEmpty
                                                ? device.deviceId
                                                : device.deviceName,
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          SizedBox(height: spacing.xs),
                                          Text(
                                            '${device.platform.isEmpty ? 'unknown' : device.platform} • ${device.hasUsableMlKemKey && device.hasUsableMlDsaKey ? 'PQC ready' : 'PQC not ready'}',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: colors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                        else
                          _buildEmptyCard('No registered devices yet.'),
                        SizedBox(height: spacing.lg),
                        AppPrimaryButton(
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
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.icon),
              label: tab.label,
            ),
        ],
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTabIndex = index;
          });
        },
      ),
    );
  }

  Widget _buildConversationTile({
    required String title,
    required String preview,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: AppSurfaceCard(
        onTap: onTap,
        child: Row(
          children: [
            AppAvatar(label: title, icon: icon),
            SizedBox(width: spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: spacing.xs),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.md),
            Icon(Icons.chevron_right_rounded, color: colors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildContactTile({
    required SessionUser sessionUser,
    required AppUser user,
    required Conversation? privateConversation,
  }) {
    final isSelf = user.id == sessionUser.id;
    final trust = _controller.trustByUserId[user.id];
    final subtitle = isSelf
        ? 'This device account'
        : user.hasUsablePqcDeviceKey
        ? trust?.isEnterpriseVerified == true
              ? 'PQC ready and verified'
              : 'PQC ready'
        : 'PQC key not ready yet';

    final colors = context.appColors;
    final spacing = context.appSpacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: AppSurfaceCard(
        onTap: isSelf ? null : () => _openPrivateChat(user),
        backgroundColor: isSelf ? colors.surfaceStrong : null,
        child: Row(
          children: [
            AppAvatar(label: user.displayName),
            SizedBox(width: spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSelf ? '${user.displayName} (You)' : user.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    '${user.devices.length} device${user.devices.length == 1 ? '' : 's'}${privateConversation != null ? ' • DM ready' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.md),
            Icon(
              isSelf ? Icons.person : Icons.chat_bubble_outline_rounded,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsHeader({
    required BuildContext context,
    required int totalUsers,
    required int readyUsers,
  }) {
    final theme = Theme.of(context);
    final spacing = context.appSpacing;
    final colors = context.appColors;
    return AppSurfaceCard(
      backgroundColor: colors.surfaceStrong,
      padding: EdgeInsets.all(spacing.xl),
      child: Row(
        children: [
          const AppAvatar(
            label: 'W',
            icon: Icons.people_alt_outlined,
            radius: 24,
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Workspace directory', style: theme.textTheme.titleLarge),
                SizedBox(height: spacing.xs),
                Text(
                  'Bu yerda saqlanganlar emas, bazadagi barcha mavjud userlar ko\'rinadi.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$totalUsers', style: theme.textTheme.titleLarge),
              Text(
                '$readyUsers PQC ready',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textMuted,
                ),
              ),
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
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final organizations = sessionUser.organizations.length;
    final workspaces = sessionUser.organizations.fold<int>(
      0,
      (sum, item) => sum + item.workspaces.length,
    );

    return AppSurfaceCard(
      backgroundColor: colors.primarySoft,
      padding: EdgeInsets.all(spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppBrandMark(size: 48),
          SizedBox(height: spacing.lg),
          Text('Profile and workspace', style: theme.textTheme.headlineSmall),
          SizedBox(height: spacing.md),
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
    final peerUser = _controller.users
        .where((user) => user.id == peerId)
        .firstOrNull;
    return peerUser?.displayName ?? conversation.title;
  }

  Widget _buildInfoRow(String label, String value) {
    final spacing = context.appSpacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String text) {
    return AppEmptyState(message: text);
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
