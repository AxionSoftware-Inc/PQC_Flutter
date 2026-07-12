import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_ui_preferences_store.dart';
import '../../../app/theme_controller.dart';
import '../../auth/session_controller.dart';
import '../../chat/application/chat_facade.dart';
import '../../crypto/durability/crypto_core_facade.dart';
import 'chat_hub_controller.dart';
import 'chat_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({
    super.key,
    required this.sessionController,
    required this.chatFacade,
    required this.cryptoCoreFacade,
    required this.themeController,
  });

  final SessionController sessionController;
  final ChatFacade chatFacade;
  final CryptoCoreFacade cryptoCoreFacade;
  final AppThemeController themeController;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  late final ChatHubController _controller;
  final TextEditingController _chatSearchController = TextEditingController();
  final TextEditingController _contactsSearchController =
      TextEditingController();
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    final sessionUser = widget.sessionController.sessionUser!;
    _controller = ChatHubController(
      chatFacade: widget.chatFacade,
      cryptoCoreFacade: widget.cryptoCoreFacade,
      currentUserId: sessionUser.id,
      sessionUserProvider: () => widget.sessionController.sessionUser!,
    )..addListener(_onControllerChanged);
    _load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _chatSearchController.dispose();
    _contactsSearchController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final chatQuery = _controller.chatState.preferences.searchQuery;
    if (_chatSearchController.text != chatQuery) {
      _chatSearchController.value = TextEditingValue(
        text: chatQuery,
        selection: TextSelection.collapsed(offset: chatQuery.length),
      );
    }
    final contactsQuery = _controller.contactsState.searchQuery;
    if (_contactsSearchController.text != contactsQuery) {
      _contactsSearchController.value = TextEditingValue(
        text: contactsQuery,
        selection: TextSelection.collapsed(offset: contactsQuery.length),
      );
    }
    setState(() {});
  }

  Future<void> _load() async {
    try {
      await _controller.load();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.sessionController.invalidateSession();
      }
    }
  }

  Future<void> _refresh() async {
    try {
      await _controller.refresh();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.sessionController.invalidateSession();
      }
    }
  }

  Future<void> _openConversation({
    required Conversation conversation,
    required String title,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          currentUserId: widget.sessionController.sessionUser!.id,
          conversation: conversation,
          title: title,
          chatFacade: widget.chatFacade,
          cryptoCoreFacade: widget.cryptoCoreFacade,
          onUnauthorized: widget.sessionController.invalidateSession,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openConversationItem(ConversationListItemState item) {
    return _openConversation(
      conversation: item.conversation,
      title: item.title,
    );
  }

  Future<void> _openContact(AppUser user) async {
    try {
      final conversation = await _controller.startChatForUser(user);
      if (!mounted) {
        return;
      }
      await _openConversation(conversation: conversation, title: user.displayName);
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.sessionController.invalidateSession();
        return;
      }
      if (!mounted) {
        return;
      }
      _showMessage(error.toString(), tone: AppStatusTone.danger);
    }
  }

  Future<void> _showConversationActions(ConversationListItemState item) async {
    final spacing = context.appSpacing;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  title: Text(item.isPinned ? 'Unpin chat' : 'Pin chat'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _controller.togglePinned(item.conversation.id);
                  },
                ),
                ListTile(
                  leading: Icon(
                    item.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                  ),
                  title: Text(
                    item.isArchived ? 'Unarchive chat' : 'Archive chat',
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _controller.toggleArchived(item.conversation.id);
                  },
                ),
                ListTile(
                  leading: Icon(
                    item.isUnread
                        ? Icons.mark_chat_read_outlined
                        : Icons.mark_chat_unread_outlined,
                  ),
                  title: Text(
                    item.isUnread ? 'Mark as read' : 'Mark as unread',
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _controller.toggleManualUnread(item.conversation.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showContactDetails(ContactListItemState item) async {
    final detail = _controller.buildContactDetailState(item.user);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ContactDetailPage(
          item: item,
          detail: detail,
          onStartChat: item.isCurrentUser
              ? null
              : () async {
                  await _openContact(item.user);
                },
          onVerify: detail.canVerify
              ? () async {
                  await _controller.verifyContact(item.user);
                  if (!mounted) {
                    return;
                  }
                  _showMessage(
                    'Contact key verified.',
                    tone: AppStatusTone.success,
                  );
                }
              : null,
        ),
      ),
    );
  }

  Future<void> _switchWorkspace(int workspaceId) async {
    await widget.sessionController.switchWorkspace(workspaceId);
    widget.chatFacade.switchWorkspaceContext(workspaceId);
    await _load();
  }

  Future<void> _showExportBackupSheet() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final spacing = context.appSpacing;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.lg,
              spacing.lg,
              spacing.lg + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  title: 'Export encrypted backup',
                  subtitle: 'Recovery passphrase bilan historical decrypt backup yaratiladi.',
                ),
                SizedBox(height: spacing.lg),
                AppTextField(
                  controller: controller,
                  labelText: 'Recovery passphrase',
                ),
                SizedBox(height: spacing.lg),
                AppPrimaryButton(
                  onPressed: () async {
                    final passphrase = controller.text.trim();
                    if (passphrase.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop();
                    final blob = await _controller.exportBackup(passphrase);
                    if (!mounted) {
                      return;
                    }
                    await _showBlobSheet(
                      title: 'Encrypted backup blob',
                      blob: blob,
                    );
                  },
                  label: const Text('Generate backup'),
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
  }

  Future<void> _showImportBackupSheet() async {
    final passphraseController = TextEditingController();
    final blobController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final spacing = context.appSpacing;
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.lg,
              spacing.lg,
              spacing.lg + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  title: 'Import encrypted backup',
                  subtitle: 'Old historical decrypt capability qayta tiklanadi.',
                ),
                SizedBox(height: spacing.lg),
                AppTextField(
                  controller: passphraseController,
                  labelText: 'Recovery passphrase',
                ),
                SizedBox(height: spacing.md),
                AppTextField(
                  controller: blobController,
                  labelText: 'Encrypted backup blob',
                  maxLines: 8,
                  minLines: 6,
                ),
                SizedBox(height: spacing.lg),
                AppPrimaryButton(
                  onPressed: () async {
                    final passphrase = passphraseController.text.trim();
                    final blob = blobController.text.trim();
                    if (passphrase.isEmpty || blob.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop();
                    await _controller.importBackup(
                      recoveryPassphrase: passphrase,
                      encryptedBlob: blob,
                    );
                  },
                  label: const Text('Restore backup'),
                ),
              ],
            ),
          ),
        );
      },
    );
    passphraseController.dispose();
    blobController.dispose();
  }

  Future<void> _showBlobSheet({
    required String title,
    required String blob,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final spacing = context.appSpacing;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionHeader(title: title),
                SizedBox(height: spacing.md),
                AppSurfaceCard(
                  child: SelectableText(
                    blob,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout({required bool forgetDevice}) async {
    if (forgetDevice) {
      await widget.sessionController.logoutAndForgetDevice();
    } else {
      await widget.sessionController.logout();
    }
  }

  void _showMessage(String message, {required AppStatusTone tone}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: switch (tone) {
          AppStatusTone.success => context.appColors.success,
          AppStatusTone.warning => context.appColors.warning,
          AppStatusTone.danger => context.appColors.danger,
          AppStatusTone.info => context.appColors.info,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.appSpacing;
    final sessionUser = widget.sessionController.sessionUser!;
    final chatState = _controller.chatState;
    final contactsState = _controller.contactsState;
    final settingsState = _controller.settingsState;
    final tabs = [
      _TabMeta(
        label: 'Chats',
        icon: Icons.chat_bubble_outline_rounded,
        title: settingsState.currentWorkspace?.name ?? 'Chats',
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
            onPressed: _refresh,
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
                    onRefresh: _refresh,
                    child: _buildChatsTab(chatState),
                  ),
                  RefreshIndicator(
                    onRefresh: _refresh,
                    child: _buildContactsTab(contactsState),
                  ),
                  RefreshIndicator(
                    onRefresh: _refresh,
                    child: _buildSettingsTab(settingsState),
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

  Widget _buildChatsTab(ChatListViewState state) {
    final spacing = context.appSpacing;
    final items = state.items;
    return ListView(
      padding: EdgeInsets.all(spacing.lg),
      children: [
        AppSearchField(
          controller: _chatSearchController,
          hintText: 'Search chats, drafts, people',
          onChanged: (value) => _controller.setChatSearchQuery(value),
        ),
        SizedBox(height: spacing.md),
        _buildChatFilterSelector(state.preferences.selectedFilter),
        SizedBox(height: spacing.lg),
        if (_controller.isLoading && items.isEmpty) ..._buildChatSkeleton()
        else if (items.isEmpty)
          _buildEmptyCard(_emptyMessageForChatState(state.preferences.selectedFilter))
        else
          for (final item in items)
            Padding(
              padding: EdgeInsets.only(bottom: spacing.sm),
              child: AppSurfaceCard(
                onTap: () => _openConversationItem(item),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _showConversationActions(item),
                  child: Row(
                    children: [
                      AppAvatar(
                        label: item.title,
                        icon: item.conversation.isGroup
                            ? Icons.forum_outlined
                            : Icons.chat_bubble_outline_rounded,
                      ),
                      SizedBox(width: spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: Theme.of(context).textTheme.titleMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                SizedBox(width: spacing.sm),
                                Text(
                                  _formatRelativeTime(item.updatedAt),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: context.appColors.textMuted,
                                      ),
                                ),
                              ],
                            ),
                            SizedBox(height: spacing.xs),
                            Text(
                              item.preview.isEmpty ? 'Open conversation' : item.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: item.hasDraft
                                    ? context.appColors.primary
                                    : context.appColors.textMuted,
                                fontWeight: item.hasDraft
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            SizedBox(height: spacing.sm),
                            Wrap(
                              spacing: spacing.xs,
                              runSpacing: spacing.xs,
                              children: [
                                if (item.isPinned)
                                  const AppBadge(
                                    label: 'Pinned',
                                    tone: AppStatusTone.info,
                                    icon: Icons.push_pin_rounded,
                                  ),
                                if (item.isUnread)
                                  AppBadge(
                                    label: item.unreadCount > 0
                                        ? 'Unread ${item.unreadCount}'
                                        : 'Unread',
                                    tone: AppStatusTone.warning,
                                    icon: Icons.mark_chat_unread_outlined,
                                  ),
                                if (item.trustBadge case final badge?)
                                  AppBadge(
                                    label: badge.label,
                                    tone: _statusTone(badge.tone),
                                  ),
                                if (item.deliveryState case final delivery?)
                                  AppBadge(
                                    label: _deliveryLabel(delivery),
                                    tone: _deliveryTone(delivery),
                                    icon: _deliveryIcon(delivery),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: spacing.md),
                      IconButton(
                        onPressed: () => _showConversationActions(item),
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildContactsTab(ContactsViewState state) {
    final spacing = context.appSpacing;
    return ListView(
      padding: EdgeInsets.all(spacing.lg),
      children: [
        AppSearchField(
          controller: _contactsSearchController,
          hintText: 'Search contacts',
          onChanged: _controller.setContactsSearchQuery,
        ),
        SizedBox(height: spacing.md),
        _buildContactsFilterSelector(state.selectedFilter),
        SizedBox(height: spacing.lg),
        if (_controller.isLoading && state.sections.isEmpty) ..._buildContactSkeleton()
        else if (state.sections.isEmpty)
          _buildEmptyCard('No contacts match the current filter.')
        else
          for (final section in state.sections) ...[
            AppSectionHeader(title: section.label),
            SizedBox(height: spacing.sm),
            for (final item in section.items)
              Padding(
                padding: EdgeInsets.only(bottom: spacing.sm),
                child: AppSurfaceCard(
                  onTap: () => _showContactDetails(item),
                  child: Row(
                    children: [
                      AppAvatar(label: item.user.displayName),
                      SizedBox(width: spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            SizedBox(height: spacing.xs),
                            Text(
                              item.deviceSummary,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: context.appColors.textMuted,
                              ),
                            ),
                            SizedBox(height: spacing.sm),
                            Wrap(
                              spacing: spacing.xs,
                              runSpacing: spacing.xs,
                              children: [
                                AppBadge(
                                  label: item.badge.label,
                                  tone: _statusTone(item.badge.tone),
                                ),
                                if (item.hasExistingConversation)
                                  const AppBadge(
                                    label: 'DM ready',
                                    tone: AppStatusTone.info,
                                    icon: Icons.chat_bubble_outline_rounded,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: spacing.md),
                      Icon(
                        item.isCurrentUser
                            ? Icons.person_outline_rounded
                            : Icons.chevron_right_rounded,
                        color: context.appColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(height: spacing.md),
          ],
      ],
    );
  }

  Widget _buildSettingsTab(SettingsViewState state) {
    final spacing = context.appSpacing;
    final theme = Theme.of(context);
    final sessionUser = state.sessionUser;
    return ListView(
      padding: EdgeInsets.all(spacing.lg),
      children: [
        AppSurfaceCard(
          backgroundColor: context.appColors.primarySoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppBrandMark(size: 48),
              SizedBox(height: spacing.lg),
              Text(
                'Profile and workspace',
                style: theme.textTheme.headlineSmall,
              ),
              SizedBox(height: spacing.md),
              _buildInfoRow('Display name', sessionUser.displayName),
              _buildInfoRow('Username', sessionUser.username),
              _buildInfoRow('Workspace', state.currentWorkspace?.name ?? 'None'),
              _buildInfoRow('Workspace ID', '${sessionUser.activeWorkspaceId}'),
              _buildInfoRow('Device ID', sessionUser.deviceId),
              _buildInfoRow('Skin', state.appSkinId),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        const AppSectionHeader(
          title: 'Security Center',
          subtitle: 'Trust, device readiness and historical decrypt health.',
        ),
        SizedBox(height: spacing.sm),
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: spacing.sm,
                runSpacing: spacing.sm,
                children: [
                  AppBadge(
                    label: '${state.security.verifiedPeersCount} verified',
                    tone: AppStatusTone.success,
                  ),
                  AppBadge(
                    label:
                        '${state.security.needsAttentionCount} need attention',
                    tone: AppStatusTone.warning,
                  ),
                  AppBadge(
                    label: '${state.security.notReadyCount} not ready',
                    tone: AppStatusTone.danger,
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              AppStatusBanner(
                message: state.security.hasHistoricalDecryptCapability
                    ? 'Historical decrypt ready. ${state.security.availableHistoricalKeysets} keysets available.'
                    : 'Historical decrypt limited. Backup restore tavsiya qilinadi.',
                tone: state.security.hasHistoricalDecryptCapability
                    ? AppStatusTone.success
                    : AppStatusTone.warning,
              ),
              SizedBox(height: spacing.md),
              AppStatusBanner(
                message: state.security.isCurrentDeviceReady
                    ? 'Current device PQC ready.'
                    : 'Current device to‘liq ready emas.',
                tone: state.security.isCurrentDeviceReady
                    ? AppStatusTone.success
                    : AppStatusTone.warning,
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        const AppSectionHeader(
          title: 'Backup & Recovery',
          subtitle: 'Encrypted export/import for durable historical decrypt.',
        ),
        SizedBox(height: spacing.sm),
        if (state.backup.statusMessage != null) ...[
          AppStatusBanner(
            message: state.backup.statusMessage!,
            tone: _statusTone(state.backup.statusTone),
          ),
          SizedBox(height: spacing.sm),
        ],
        AppSurfaceCard(
          child: Column(
            children: [
              _buildActionRow(
                icon: Icons.download_rounded,
                title: 'Export encrypted backup',
                subtitle: 'Recovery passphrase bilan backup yarating.',
                onTap: _showExportBackupSheet,
              ),
              SizedBox(height: spacing.sm),
              _buildActionRow(
                icon: Icons.upload_rounded,
                title: 'Import encrypted backup',
                subtitle: 'Old history decrypt capability tiklanadi.',
                onTap: _showImportBackupSheet,
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        const AppSectionHeader(
          title: 'Devices & Sessions',
          subtitle: 'Current device and visible registered devices.',
        ),
        SizedBox(height: spacing.sm),
        if (state.currentDevice != null)
          AppSurfaceCard(
            backgroundColor: context.appColors.surfaceStrong,
            child: Row(
              children: [
                const AppAvatar(
                  label: 'D',
                  icon: Icons.shield_outlined,
                  radius: 20,
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.currentDevice!.deviceName.isEmpty
                            ? 'Current device'
                            : state.currentDevice!.deviceName,
                        style: theme.textTheme.titleMedium,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        '${state.currentDevice!.platform.isEmpty ? 'unknown' : state.currentDevice!.platform} • ${state.currentDevice!.status}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                AppBadge(
                  label: state.currentDevice!.hasUsableMlKemKey &&
                          state.currentDevice!.hasUsableMlDsaKey
                      ? 'PQC ready'
                      : 'Needs setup',
                  tone: state.currentDevice!.hasUsableMlKemKey &&
                          state.currentDevice!.hasUsableMlDsaKey
                      ? AppStatusTone.success
                      : AppStatusTone.warning,
                ),
              ],
            ),
          )
        else
          _buildEmptyCard('Current device information is not available.'),
        SizedBox(height: spacing.sm),
        for (final device in state.devices)
          Padding(
            padding: EdgeInsets.only(bottom: spacing.sm),
            child: AppSurfaceCard(
              child: Row(
                children: [
                  const AppAvatar(
                    label: 'D',
                    icon: Icons.devices_outlined,
                    radius: 18,
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.deviceName.isEmpty ? device.deviceId : device.deviceName,
                          style: theme.textTheme.titleMedium,
                        ),
                        SizedBox(height: spacing.xs),
                        Text(
                          '${device.platform.isEmpty ? 'unknown' : device.platform} • ${device.status} • fingerprint ${device.profileFingerprint.isEmpty ? 'missing' : 'present'}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.appColors.textMuted,
                          ),
                        ),
                        if (device.lastSeenAt != null) ...[
                          SizedBox(height: spacing.xs),
                          Text(
                            'Last seen ${_formatRelativeTime(device.lastSeenAt!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context.appColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AppBadge(
                    label: device.hasUsableMlKemKey && device.hasUsableMlDsaKey
                        ? 'Ready'
                        : 'Not ready',
                    tone: device.hasUsableMlKemKey && device.hasUsableMlDsaKey
                        ? AppStatusTone.success
                        : AppStatusTone.warning,
                  ),
                ],
              ),
            ),
          ),
        SizedBox(height: spacing.lg),
        const AppSectionHeader(
          title: 'Preferences',
          subtitle: 'Local product settings for inbox behavior.',
        ),
        SizedBox(height: spacing.sm),
        AppSurfaceCard(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: widget.themeController.themeMode == ThemeMode.dark,
                title: const Text('Dark mode'),
                subtitle: const Text('Light va dark ko‘rinish o‘rtasida almashish.'),
                onChanged: (value) {
                  widget.themeController.setThemeMode(
                    value ? ThemeMode.dark : ThemeMode.light,
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.appPreferences.showArchivedByDefault,
                title: const Text('Show archived in main inbox'),
                subtitle: const Text('Archived chats “All” ichida ham ko‘rinsin.'),
                onChanged: (value) {
                  _controller.updateAppPreferences(
                    state.appPreferences.copyWith(showArchivedByDefault: value),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.appPreferences.compactListMode,
                title: const Text('Compact list mode'),
                subtitle: const Text('Tiles shorter va zichroq ko‘rinadi.'),
                onChanged: (value) {
                  _controller.updateAppPreferences(
                    state.appPreferences.copyWith(compactListMode: value),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.appPreferences.keepDrafts,
                title: const Text('Keep drafts'),
                subtitle: const Text('Composer draftlari avtomatik saqlansin.'),
                onChanged: (value) {
                  _controller.updateAppPreferences(
                    state.appPreferences.copyWith(keepDrafts: value),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.appPreferences.preferManualRefreshHints,
                title: const Text('Prefer manual refresh hints'),
                subtitle: const Text('Auto refresh o‘rniga ko‘proq manual affordance.'),
                onChanged: (value) {
                  _controller.updateAppPreferences(
                    state.appPreferences.copyWith(
                      preferManualRefreshHints: value,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        const AppSectionHeader(
          title: 'About & Support',
          subtitle: 'Build identity and support contact.',
        ),
        SizedBox(height: spacing.sm),
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Version', state.appVersion),
              _buildInfoRow('Support', state.supportEmail),
              _buildInfoRow('API', state.apiBaseUrl),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        Row(
          children: [
            Expanded(
              child: AppSecondaryButton(
                onPressed: () => _logout(forgetDevice: false),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: AppPrimaryButton(
                onPressed: () => _logout(forgetDevice: true),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Forget device'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChatFilterSelector(ChatListFilter filter) {
    return SegmentedButton<ChatListFilter>(
      segments: const [
        ButtonSegment(value: ChatListFilter.all, label: Text('All')),
        ButtonSegment(value: ChatListFilter.unread, label: Text('Unread')),
        ButtonSegment(value: ChatListFilter.pinned, label: Text('Pinned')),
        ButtonSegment(value: ChatListFilter.archived, label: Text('Archived')),
      ],
      selected: {filter},
      onSelectionChanged: (selection) {
        _controller.setChatFilter(selection.first);
      },
    );
  }

  Widget _buildContactsFilterSelector(ContactsTrustFilter filter) {
    return SegmentedButton<ContactsTrustFilter>(
      segments: const [
        ButtonSegment(value: ContactsTrustFilter.all, label: Text('All')),
        ButtonSegment(
          value: ContactsTrustFilter.verified,
          label: Text('Verified'),
        ),
        ButtonSegment(
          value: ContactsTrustFilter.needsAttention,
          label: Text('Attention'),
        ),
        ButtonSegment(
          value: ContactsTrustFilter.notReady,
          label: Text('Not ready'),
        ),
      ],
      selected: {filter},
      onSelectionChanged: (selection) {
        _controller.setContactsFilter(selection.first);
      },
    );
  }

  List<Widget> _buildChatSkeleton() {
    final spacing = context.appSpacing;
    return List<Widget>.generate(
      4,
      (index) => Padding(
        padding: EdgeInsets.only(bottom: spacing.sm),
        child: AppSurfaceCard(
          child: Row(
            children: [
              const AppAvatar(label: 'S'),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSkeletonBlock(height: 16, width: 160),
                    SizedBox(height: spacing.sm),
                    const AppSkeletonBlock(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContactSkeleton() {
    final spacing = context.appSpacing;
    return List<Widget>.generate(
      4,
      (index) => Padding(
        padding: EdgeInsets.only(bottom: spacing.sm),
        child: AppSurfaceCard(
          child: Row(
            children: [
              const AppAvatar(label: 'S'),
              SizedBox(width: spacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonBlock(height: 16, width: 180),
                    SizedBox(height: 10),
                    AppSkeletonBlock(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final spacing = context.appSpacing;
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          AppAvatar(label: title, icon: icon, radius: 18),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: spacing.xs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.appColors.textMuted),
        ],
      ),
    );
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

  String _emptyMessageForChatState(ChatListFilter filter) {
    switch (filter) {
      case ChatListFilter.unread:
        return 'Unread chat topilmadi.';
      case ChatListFilter.pinned:
        return 'Pinned chatlar hali yo‘q.';
      case ChatListFilter.archived:
        return 'Archived chatlar hali yo‘q.';
      case ChatListFilter.all:
        return 'Hali chatlar yo‘q. Contacts bo‘limidan suhbat boshlashingiz mumkin.';
    }
  }

  String _formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inMinutes < 1) {
      return 'now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours}h';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays}d';
    }
    return '${time.day}/${time.month}';
  }

  String _deliveryLabel(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.pending:
        return 'Sending';
      case MessageDeliveryState.failedRetryable:
        return 'Failed';
      case MessageDeliveryState.failedPermanent:
        return 'Blocked';
      case MessageDeliveryState.sent:
        return 'Sent';
    }
  }

  IconData _deliveryIcon(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.pending:
        return Icons.schedule_rounded;
      case MessageDeliveryState.failedRetryable:
        return Icons.refresh_rounded;
      case MessageDeliveryState.failedPermanent:
        return Icons.block_rounded;
      case MessageDeliveryState.sent:
        return Icons.check_rounded;
    }
  }

  AppStatusTone _deliveryTone(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.pending:
        return AppStatusTone.info;
      case MessageDeliveryState.failedRetryable:
        return AppStatusTone.warning;
      case MessageDeliveryState.failedPermanent:
        return AppStatusTone.danger;
      case MessageDeliveryState.sent:
        return AppStatusTone.success;
    }
  }

  AppStatusTone _statusTone(UiStatusTone tone) {
    switch (tone) {
      case UiStatusTone.success:
        return AppStatusTone.success;
      case UiStatusTone.warning:
        return AppStatusTone.warning;
      case UiStatusTone.danger:
        return AppStatusTone.danger;
      case UiStatusTone.info:
        return AppStatusTone.info;
    }
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

class _ContactDetailPage extends StatelessWidget {
  const _ContactDetailPage({
    required this.item,
    required this.detail,
    required this.onStartChat,
    required this.onVerify,
  });

  final ContactListItemState item;
  final ContactDetailState detail;
  final Future<void> Function()? onStartChat;
  final Future<void> Function()? onVerify;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Contact details'),
      ),
      body: ListView(
        padding: EdgeInsets.all(spacing.lg),
        children: [
          AppSurfaceCard(
            child: Row(
              children: [
                AppAvatar(label: item.user.displayName, radius: 28),
                SizedBox(width: spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.user.displayName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        item.user.username,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.lg),
          AppBadge(
            label: detail.badge.label,
            tone: _mapTone(detail.badge.tone),
          ),
          SizedBox(height: spacing.md),
          AppStatusBanner(
            message: detail.badge.details ?? detail.deviceSummary,
            tone: _mapTone(detail.badge.tone),
          ),
          SizedBox(height: spacing.lg),
          const AppSectionHeader(
            title: 'Devices',
            subtitle: 'Current visible multi-device roster.',
          ),
          SizedBox(height: spacing.sm),
          if (detail.devices.isEmpty)
            const AppEmptyState(
              message: 'No visible devices for this contact.',
              icon: Icons.devices_outlined,
            )
          else
            for (final device in detail.devices)
              Padding(
                padding: EdgeInsets.only(bottom: spacing.sm),
                child: AppSurfaceCard(
                  child: Row(
                    children: [
                      const AppAvatar(
                        label: 'D',
                        icon: Icons.devices_outlined,
                        radius: 18,
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
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            SizedBox(height: spacing.xs),
                            Text(
                              '${device.platform.isEmpty ? 'unknown' : device.platform} • ${device.isActive ? 'active' : device.status} • ${device.hasUsableMlKemKey && device.hasUsableMlDsaKey ? 'ready' : 'not ready'}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: context.appColors.textMuted,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          SizedBox(height: spacing.lg),
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton(
                  onPressed: item.isCurrentUser
                      ? null
                      : () async {
                          await onStartChat?.call();
                          if (context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                  label: Text(
                    detail.hasExistingConversation ? 'Open chat' : 'Start chat',
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: AppSecondaryButton(
                  onPressed: onVerify == null
                      ? null
                      : () async {
                          await onVerify!.call();
                          if (context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                  label: const Text('Verify key'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  AppStatusTone _mapTone(UiStatusTone tone) {
    switch (tone) {
      case UiStatusTone.success:
        return AppStatusTone.success;
      case UiStatusTone.warning:
        return AppStatusTone.warning;
      case UiStatusTone.danger:
        return AppStatusTone.danger;
      case UiStatusTone.info:
        return AppStatusTone.info;
    }
  }
}
