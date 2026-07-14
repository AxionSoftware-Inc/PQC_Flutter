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
    required this.apiClient,
  });

  final SessionController sessionController;
  final ChatFacade chatFacade;
  final CryptoCoreFacade cryptoCoreFacade;
  final AppThemeController themeController;
  final ApiClient apiClient;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  late final ChatHubController _controller;
  final TextEditingController _chatSearchController = TextEditingController();
  final TextEditingController _contactsSearchController =
      TextEditingController();
  int _selectedTabIndex = 0;
  bool _recoveryPromptShown = false;
  bool _notificationsEnabled = true;
  bool _notificationPreviewsEnabled = true;
  bool _readReceiptsEnabled = true;
  bool _typingIndicatorsEnabled = true;
  String _lastSeenVisibility = 'contacts';
  String _onlineVisibility = 'contacts';
  bool _accountSettingsHydrated = false;
  final Set<int> _selectedConversationIds = <int>{};

  @override
  void initState() {
    super.initState();
    final sessionUser = widget.sessionController.sessionUser!;
    _controller = ChatHubController(
      chatFacade: widget.chatFacade,
      cryptoCoreFacade: widget.cryptoCoreFacade,
      currentUserId: sessionUser.id,
      sessionUserProvider: () => widget.sessionController.sessionUser!,
      apiClient: widget.apiClient,
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
    final accountSettings = _controller.accountSettings;
    if (!_accountSettingsHydrated && accountSettings.isNotEmpty) {
      _notificationsEnabled =
          accountSettings['notifications_enabled'] as bool? ?? true;
      _notificationPreviewsEnabled =
          accountSettings['notification_previews'] as bool? ?? true;
      _readReceiptsEnabled =
          accountSettings['read_receipts_enabled'] as bool? ?? true;
      _typingIndicatorsEnabled =
          accountSettings['typing_indicators_enabled'] as bool? ?? true;
      _lastSeenVisibility =
          accountSettings['last_seen_visibility'] as String? ?? 'contacts';
      _onlineVisibility =
          accountSettings['online_visibility'] as String? ?? 'contacts';
      _accountSettingsHydrated = true;
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
      await _syncServerRecovery();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.sessionController.invalidateSession();
      }
    }
  }

  Future<void> _syncServerRecovery() async {
    if (_recoveryPromptShown || !mounted) return;
    _recoveryPromptShown = true;
    await _controller.syncEnterpriseRecoveryManifest();
    if (mounted) await _controller.refresh();
  }

  Future<void> _showPendingRecoveryApprovals() async {
    final approvals = await _controller.pendingRecoveryApprovals();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('History recovery requests'),
              subtitle: Text(
                'Approve only a device you recognize. Approval expires automatically.',
              ),
            ),
            if (approvals.isEmpty)
              const ListTile(title: Text('No pending requests')),
            for (final approval in approvals)
              ListTile(
                leading: const Icon(Icons.devices_other_outlined),
                title: Text(
                  approval['requesting_device_id'] as String? ?? 'New device',
                ),
                subtitle: Text('Requested ${approval['created_at'] ?? ''}'),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Deny',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () async {
                        await _controller.decideRecoveryApproval(
                          approvalId: approval['id'] as int,
                          approved: false,
                        );
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                    IconButton(
                      tooltip: 'Approve',
                      icon: const Icon(Icons.check_rounded),
                      onPressed: () async {
                        await _controller.decideRecoveryApproval(
                          approvalId: approval['id'] as int,
                          approved: true,
                        );
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<String?> _showRecoveryPinDialog({required bool hasServerBackup}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          hasServerBackup ? 'Restore chat history' : 'Protect chat history',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasServerBackup
                  ? 'This account has an encrypted recovery backup. Enter your recovery PIN to open older messages on this device.'
                  : 'Create a recovery PIN. It protects your chat keys and lets you restore history after reinstalling or changing devices.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: const InputDecoration(labelText: 'Recovery PIN'),
            ),
          ],
        ),
        actions: [
          if (hasServerBackup)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: () {
              final pin = controller.text.trim();
              if (pin.length < 6) return;
              Navigator.of(dialogContext).pop(pin);
            },
            child: Text(hasServerBackup ? 'Restore' : 'Save backup'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
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
      await _openConversation(
        conversation: conversation,
        title: user.displayName,
      );
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
                    item.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
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

  // ignore: unused_element
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
                  subtitle:
                      'Recovery passphrase bilan historical decrypt backup yaratiladi.',
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
                      title: 'Serverga saqlandi: encrypted backup blob',
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

  // ignore: unused_element
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
                  subtitle:
                      'Old historical decrypt capability qayta tiklanadi.',
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
                SizedBox(height: spacing.md),
                AppSecondaryButton(
                  onPressed: () async {
                    final blob = await _controller.downloadServerBackup();
                    if (blob == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Serverda backup topilmadi.'),
                          ),
                        );
                      }
                      return;
                    }
                    blobController.text = blob;
                  },
                  label: const Text('Load backup from server'),
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
        toolbarHeight: 68,
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
            if (_controller.isLoading)
              const LinearProgressIndicator(minHeight: 2),
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
                    child: _buildSettingsOverview(settingsState),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.appColors.surface,
          border: Border(top: BorderSide(color: context.appColors.border)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 66,
            backgroundColor: context.appColors.surface,
            indicatorColor: context.appColors.primarySoft,
            labelTextStyle: WidgetStatePropertyAll(
              theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          child: NavigationBar(
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
        ),
      ),
    );
  }

  Widget _buildChatsTab(ChatListViewState state) {
    final spacing = context.appSpacing;
    final items = state.items;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.sm,
        spacing.lg,
        spacing.lg,
      ),
      children: [
        if (_selectedConversationIds.isNotEmpty) ...[
          AppSurfaceCard(
            backgroundColor: context.appColors.primarySoft,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Clear selection',
                  onPressed: () => setState(_selectedConversationIds.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
                Expanded(
                  child: Text(
                    '${_selectedConversationIds.length} selected',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Archive selected',
                  onPressed: _archiveSelectedConversations,
                  icon: const Icon(Icons.archive_outlined),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.sm),
        ],
        AppSearchField(
          controller: _chatSearchController,
          hintText: 'Search chats, drafts, people',
          onChanged: (value) => _controller.setChatSearchQuery(value),
        ),
        SizedBox(height: spacing.md),
        _buildChatFilterSelector(state.preferences.selectedFilter),
        SizedBox(height: spacing.lg),
        if (_controller.isLoading && items.isEmpty)
          ..._buildChatSkeleton()
        else if (items.isEmpty)
          _buildEmptyCard(
            _emptyMessageForChatState(state.preferences.selectedFilter),
          )
        else
          for (final item in items)
            Dismissible(
              key: ValueKey('conversation-${item.conversation.id}'),
              direction: DismissDirection.horizontal,
              background: _swipeActionBackground(
                alignment: Alignment.centerLeft,
                color: context.appColors.primary,
                icon: Icons.mark_chat_read_outlined,
                label: 'Unread',
              ),
              secondaryBackground: _swipeActionBackground(
                alignment: Alignment.centerRight,
                color: context.appColors.warning,
                icon: item.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                label: item.isArchived ? 'Restore' : 'Archive',
              ),
              confirmDismiss: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  await _controller.toggleManualUnread(item.conversation.id);
                } else {
                  await _controller.toggleArchived(item.conversation.id);
                }
                return false;
              },
              child: _ConversationListRow(
                item: item,
                selected: _selectedConversationIds.contains(
                  item.conversation.id,
                ),
                onTap: () => _selectedConversationIds.isNotEmpty
                    ? _toggleConversationSelection(item.conversation.id)
                    : _openConversationItem(item),
                onLongPress: () =>
                    _toggleConversationSelection(item.conversation.id),
                onMorePressed: () => _showConversationActions(item),
                relativeTime: _formatRelativeTime(item.updatedAt),
              ),
            ),
      ],
    );
  }

  Widget _swipeActionBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      alignment: alignment,
      margin: EdgeInsets.symmetric(vertical: context.appSpacing.xs),
      padding: EdgeInsets.symmetric(horizontal: context.appSpacing.lg),
      color: color.withValues(alpha: 0.14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          SizedBox(width: context.appSpacing.xs),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  void _toggleConversationSelection(int conversationId) {
    setState(() {
      if (!_selectedConversationIds.add(conversationId)) {
        _selectedConversationIds.remove(conversationId);
      }
    });
  }

  Future<void> _archiveSelectedConversations() async {
    final ids = List<int>.of(_selectedConversationIds);
    for (final id in ids) {
      await _controller.toggleArchived(id);
    }
    if (mounted) setState(_selectedConversationIds.clear);
  }

  Widget _buildContactsTab(ContactsViewState state) {
    final spacing = context.appSpacing;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.sm,
        spacing.lg,
        spacing.lg,
      ),
      children: [
        AppSearchField(
          controller: _contactsSearchController,
          hintText: 'Search contacts',
          onChanged: _controller.setContactsSearchQuery,
        ),
        SizedBox(height: spacing.md),
        _buildContactsFilterSelector(state.selectedFilter),
        SizedBox(height: spacing.lg),
        if (_controller.isLoading && state.sections.isEmpty)
          ..._buildContactSkeleton()
        else if (state.sections.isEmpty)
          _buildEmptyCard('No contacts match the current filter.')
        else
          for (final section in state.sections) ...[
            AppSectionHeader(title: section.label),
            SizedBox(height: spacing.xs),
            for (final item in section.items)
              _ContactListRow(
                item: item,
                onTap: () => _showContactDetails(item),
              ),
            SizedBox(height: spacing.md),
          ],
      ],
    );
  }

  // Legacy all-in-one layout kept temporarily as a migration reference.
  // ignore: unused_element
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
              _buildInfoRow(
                'Workspace',
                state.currentWorkspace?.name ?? 'None',
              ),
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
          subtitle: 'Automatic encrypted recovery linked to this account.',
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
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Enterprise history recovery'),
                subtitle: const Text(
                  'AWS KMS escrow manifestini faqat siz Restore history tugmasini bosganingizda import qilamiz.',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Recovery requests',
                      icon: const Icon(Icons.verified_user_outlined),
                      onPressed: _showPendingRecoveryApprovals,
                    ),
                    IconButton(
                      tooltip: 'Restore history',
                      icon: const Icon(Icons.restore_rounded),
                      onPressed: () async {
                        try {
                          await _controller.restoreEnterpriseRecovery();
                        } catch (error) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      },
                    ),
                  ],
                ),
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
                  label:
                      state.currentDevice!.hasUsableMlKemKey &&
                          state.currentDevice!.hasUsableMlDsaKey
                      ? 'PQC ready'
                      : 'Needs setup',
                  tone:
                      state.currentDevice!.hasUsableMlKemKey &&
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
                          device.deviceName.isEmpty
                              ? device.deviceId
                              : device.deviceName,
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
                subtitle: const Text(
                  'Light va dark ko‘rinish o‘rtasida almashish.',
                ),
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
                subtitle: const Text(
                  'Archived chats “All” ichida ham ko‘rinsin.',
                ),
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
                subtitle: const Text(
                  'Auto refresh o‘rniga ko‘proq manual affordance.',
                ),
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

  Widget _buildSettingsOverview(SettingsViewState state) {
    final spacing = context.appSpacing;
    return ListView(
      padding: EdgeInsets.all(spacing.lg),
      children: [
        const AppSectionHeader(
          title: 'Settings',
          subtitle: 'Choose a section to manage this account.',
        ),
        SizedBox(height: spacing.md),
        _settingsSection(
          'Account',
          'Profile, workspace and session',
          Icons.person_outline_rounded,
          _buildAccountSettings,
        ),
        _settingsSection(
          'Security',
          'Trust, keys and decrypt health',
          Icons.shield_outlined,
          _buildSecuritySettings,
        ),
        _settingsSection(
          'Devices',
          'Registered devices and revoke',
          Icons.devices_outlined,
          _buildDevicesSettings,
        ),
        _settingsSection(
          'Backup & Recovery',
          'Restore and portable encrypted backups',
          Icons.backup_outlined,
          _buildBackupSettings,
        ),
        _settingsSection(
          'Notifications & Privacy',
          'Alerts, typing and presence',
          Icons.notifications_outlined,
          _buildNotificationsSettings,
        ),
        _settingsSection(
          'Appearance & Chats',
          'Theme, drafts and inbox layout',
          Icons.palette_outlined,
          _buildAppearanceSettings,
        ),
        _settingsSection(
          'About & Support',
          'Version and support details',
          Icons.info_outline_rounded,
          _buildAboutSettings,
        ),
      ],
    );
  }

  Widget _settingsSection(
    String title,
    String subtitle,
    IconData icon,
    Widget Function(SettingsViewState) builder,
  ) {
    final spacing = context.appSpacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: AppSurfaceCard(
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: spacing.md),
          leading: Icon(icon, color: context.appColors.primary),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _SettingsPage(
                title: title,
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (_, _) => builder(_controller.settingsState),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsList(List<Widget> children) => ListView(
    padding: EdgeInsets.all(context.appSpacing.lg),
    children: children,
  );

  Widget _buildAccountSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    final session = state.sessionUser;
    return _settingsList([
      AppSurfaceCard(
        backgroundColor: context.appColors.primarySoft,
        child: Column(
          children: [
            AppAvatar(label: session.displayName, radius: 38),
            SizedBox(height: spacing.md),
            Text(
              session.displayName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              session.username,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: spacing.lg),
      const AppSectionHeader(title: 'Workspace'),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          children: [
            _buildInfoRow('Current', state.currentWorkspace?.name ?? 'None'),
            for (final organization in session.organizations)
              for (final workspace in organization.workspaces)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    workspace.id == session.activeWorkspaceId
                        ? Icons.check_circle_rounded
                        : Icons.apartment_outlined,
                  ),
                  title: Text(workspace.name),
                  subtitle: Text(organization.name),
                  onTap: workspace.id == session.activeWorkspaceId
                      ? null
                      : () => _switchWorkspace(workspace.id),
                ),
          ],
        ),
      ),
      SizedBox(height: spacing.lg),
      AppSurfaceCard(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Log out'),
              subtitle: const Text('Keep this device registered.'),
              onTap: () => _logout(forgetDevice: false),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: context.appColors.danger,
              ),
              title: const Text('Forget this device'),
              subtitle: const Text(
                'Remove this local session and local history.',
              ),
              onTap: () => _logout(forgetDevice: true),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildSecuritySettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Security Center',
        subtitle: 'Trust and historical decrypt readiness.',
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
                  label: '${state.security.needsAttentionCount} need attention',
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
                  : 'Historical decrypt is limited. Restore a backup for older messages.',
              tone: state.security.hasHistoricalDecryptCapability
                  ? AppStatusTone.success
                  : AppStatusTone.warning,
            ),
            SizedBox(height: spacing.sm),
            AppStatusBanner(
              message: state.security.isCurrentDeviceReady
                  ? 'This device is ready for secure messaging.'
                  : 'This device needs key setup.',
              tone: state.security.isCurrentDeviceReady
                  ? AppStatusTone.success
                  : AppStatusTone.warning,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildDevicesSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Devices & Sessions',
        subtitle: 'Revoke only devices you do not recognize.',
      ),
      SizedBox(height: spacing.sm),
      for (final device in state.devices)
        Padding(
          padding: EdgeInsets.only(bottom: spacing.sm),
          child: AppSurfaceCard(
            child: ListTile(
              leading: Icon(
                device.deviceId == state.sessionUser.deviceId
                    ? Icons.phone_android_rounded
                    : Icons.devices_outlined,
              ),
              title: Text(
                device.deviceName.isEmpty ? device.deviceId : device.deviceName,
              ),
              subtitle: Text(
                '${device.platform.isEmpty ? 'Unknown platform' : device.platform} • ${device.status}',
              ),
              trailing: device.deviceId == state.sessionUser.deviceId
                  ? const AppBadge(
                      label: 'This device',
                      tone: AppStatusTone.info,
                    )
                  : IconButton(
                      tooltip: 'Revoke device',
                      icon: Icon(
                        Icons.remove_circle_outline_rounded,
                        color: context.appColors.danger,
                      ),
                      onPressed: () => _confirmDeviceRevoke(device),
                    ),
            ),
          ),
        ),
      if (state.devices.isEmpty)
        _buildEmptyCard('No registered devices found.'),
    ]);
  }

  Widget _buildBackupSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Backup & Recovery',
        subtitle: 'Recover encrypted history after reinstall or device switch.',
      ),
      SizedBox(height: spacing.sm),
      if (state.backup.statusMessage != null)
        AppStatusBanner(
          message: state.backup.statusMessage!,
          tone: _statusTone(state.backup.statusTone),
        ),
      AppSurfaceCard(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Restore encrypted history'),
              subtitle: const Text(
                'Import the account recovery manifest after approval.',
              ),
              onTap: _restoreEnterpriseRecovery,
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Recovery approvals'),
              subtitle: const Text('Review requests from your other devices.'),
              onTap: _showPendingRecoveryApprovals,
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Export encrypted backup'),
              onTap: _showExportBackupSheet,
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Import encrypted backup'),
              onTap: _showImportBackupSheet,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildNotificationsSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Notifications',
        subtitle: 'These preferences synchronize with your account.',
      ),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notificationsEnabled,
              title: const Text('Notifications'),
              onChanged: (value) =>
                  _setAccountBool('notifications_enabled', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notificationPreviewsEnabled,
              title: const Text('Notification previews'),
              subtitle: const Text('Include message text in alerts.'),
              onChanged: (value) =>
                  _setAccountBool('notification_previews', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _readReceiptsEnabled,
              title: const Text('Read receipts'),
              onChanged: (value) =>
                  _setAccountBool('read_receipts_enabled', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _typingIndicatorsEnabled,
              title: const Text('Typing indicators'),
              onChanged: (value) =>
                  _setAccountBool('typing_indicators_enabled', value),
            ),
            _visibilitySetting(
              'Last seen visibility',
              _lastSeenVisibility,
              _setLastSeenVisibility,
            ),
            _visibilitySetting(
              'Online visibility',
              _onlineVisibility,
              _setOnlineVisibility,
            ),
          ],
        ),
      ),
      SizedBox(height: spacing.lg),
      const AppSurfaceCard(
        child: ListTile(
          leading: Icon(Icons.lock_outline_rounded),
          title: Text('Message content'),
          subtitle: Text(
            'Message content remains end-to-end encrypted and is not readable by the server.',
          ),
        ),
      ),
    ]);
  }

  Widget _visibilitySetting(
    String title,
    String value,
    ValueChanged<String> onChanged,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: 'everyone', child: Text('Everyone')),
          DropdownMenuItem(value: 'contacts', child: Text('Contacts')),
          DropdownMenuItem(value: 'nobody', child: Text('Nobody')),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    ),
  );

  Widget _buildAppearanceSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Appearance & Chats',
        subtitle: 'Local display and composer preferences.',
      ),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.themeController.themeMode == ThemeMode.dark,
              title: const Text('Dark mode'),
              onChanged: (value) => widget.themeController.setThemeMode(
                value ? ThemeMode.dark : ThemeMode.light,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.appPreferences.compactListMode,
              title: const Text('Compact chat list'),
              onChanged: (value) => _controller.updateAppPreferences(
                state.appPreferences.copyWith(compactListMode: value),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.appPreferences.showArchivedByDefault,
              title: const Text('Show archived chats'),
              onChanged: (value) => _controller.updateAppPreferences(
                state.appPreferences.copyWith(showArchivedByDefault: value),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.appPreferences.keepDrafts,
              title: const Text('Keep drafts'),
              onChanged: (value) => _controller.updateAppPreferences(
                state.appPreferences.copyWith(keepDrafts: value),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildAboutSettings(SettingsViewState state) => _settingsList([
    const AppSectionHeader(title: 'About & Support'),
    SizedBox(height: context.appSpacing.sm),
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
  ]);

  Future<void> _restoreEnterpriseRecovery() async {
    try {
      await _controller.restoreEnterpriseRecovery();
    } catch (error) {
      if (mounted) _showMessage(error.toString(), tone: AppStatusTone.danger);
    }
  }

  void _setAccountBool(String key, bool value) {
    setState(() {
      switch (key) {
        case 'notifications_enabled':
          _notificationsEnabled = value;
        case 'notification_previews':
          _notificationPreviewsEnabled = value;
        case 'read_receipts_enabled':
          _readReceiptsEnabled = value;
        case 'typing_indicators_enabled':
          _typingIndicatorsEnabled = value;
      }
    });
    _controller.updateAccountSettings({key: value});
  }

  void _setLastSeenVisibility(String value) {
    setState(() => _lastSeenVisibility = value);
    _controller.updateAccountSettings({'last_seen_visibility': value});
  }

  void _setOnlineVisibility(String value) {
    setState(() => _onlineVisibility = value);
    _controller.updateAccountSettings({'online_visibility': value});
  }

  Future<void> _confirmDeviceRevoke(AppUserDevice device) async {
    final label = device.deviceName.isEmpty
        ? device.deviceId
        : device.deviceName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke device?'),
        content: Text('$label will no longer access this account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _controller.revokeDevice(device.deviceId);
      if (mounted) _showMessage('Device revoked.', tone: AppStatusTone.success);
    } catch (error) {
      if (mounted) _showMessage(error.toString(), tone: AppStatusTone.danger);
    }
  }

  Widget _buildChatFilterSelector(ChatListFilter filter) {
    return _FilterStrip<ChatListFilter>(
      selected: filter,
      options: const [
        _FilterOption(value: ChatListFilter.all, label: 'All'),
        _FilterOption(value: ChatListFilter.unread, label: 'Unread'),
        _FilterOption(value: ChatListFilter.pinned, label: 'Pinned'),
        _FilterOption(value: ChatListFilter.archived, label: 'Archived'),
      ],
      onSelected: _controller.setChatFilter,
    );
  }

  Widget _buildContactsFilterSelector(ContactsTrustFilter filter) {
    return _FilterStrip<ContactsTrustFilter>(
      selected: filter,
      options: const [
        _FilterOption(value: ContactsTrustFilter.all, label: 'All'),
        _FilterOption(value: ContactsTrustFilter.verified, label: 'Verified'),
        _FilterOption(
          value: ContactsTrustFilter.needsAttention,
          label: 'Attention',
        ),
        _FilterOption(value: ContactsTrustFilter.notReady, label: 'Not ready'),
      ],
      onSelected: _controller.setContactsFilter,
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

  // ignore: unused_element
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
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
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

class _ConversationListRow extends StatelessWidget {
  const _ConversationListRow({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMorePressed,
    required this.relativeTime,
  });

  final ConversationListItemState item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMorePressed;
  final String relativeTime;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final isAttention =
        item.trustBadge?.tone == UiStatusTone.warning ||
        item.trustBadge?.tone == UiStatusTone.danger;
    final preview = item.hasDraft
        ? 'Draft: ${item.draftPreview!.trim()}'
        : item.preview.isEmpty
        ? 'Open conversation'
        : item.preview;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(context.appRadii.md),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: spacing.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: 0.72)),
            ),
          ),
          child: Row(
            children: [
              selected
                  ? IconButton.filledTonal(
                      onPressed: onLongPress,
                      icon: const Icon(Icons.check_rounded),
                      tooltip: 'Selected',
                    )
                  : AppAvatar(
                      label: item.title,
                      icon: item.conversation.isGroup
                          ? Icons.forum_outlined
                          : null,
                      radius: 25,
                    ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: item.isUnread
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                      ),
                                ),
                              ),
                              if (item.isPinned) ...[
                                SizedBox(width: spacing.xs),
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 14,
                                  color: colors.textMuted,
                                ),
                              ],
                              if (isAttention) ...[
                                SizedBox(width: spacing.xs),
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 15,
                                  color: colors.warning,
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(width: spacing.sm),
                        Text(
                          relativeTime,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: item.isUnread
                                    ? colors.primary
                                    : colors.textMuted,
                                fontWeight: item.isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.xs),
                    Row(
                      children: [
                        if (item.deliveryState != null) ...[
                          Icon(
                            _deliveryIcon(item.deliveryState!),
                            size: 15,
                            color: _deliveryColor(colors, item.deliveryState!),
                          ),
                          SizedBox(width: spacing.xs),
                        ],
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: item.hasDraft
                                      ? colors.primary
                                      : colors.textMuted,
                                  fontWeight: item.hasDraft
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                          ),
                        ),
                        if (item.isUnread) ...[
                          SizedBox(width: spacing.sm),
                          Container(
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              item.unreadCount > 0 ? '${item.unreadCount}' : '',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.xs),
              IconButton(
                onPressed: onMorePressed,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.more_horiz_rounded, color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _deliveryIcon(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.pending:
        return Icons.schedule_rounded;
      case MessageDeliveryState.failedRetryable:
        return Icons.error_outline_rounded;
      case MessageDeliveryState.failedPermanent:
        return Icons.block_rounded;
      case MessageDeliveryState.sent:
        return Icons.done_all_rounded;
    }
  }

  Color _deliveryColor(AppColors colors, MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.pending:
        return colors.textMuted;
      case MessageDeliveryState.failedRetryable:
      case MessageDeliveryState.failedPermanent:
        return colors.danger;
      case MessageDeliveryState.sent:
        return colors.primary;
    }
  }
}

class _ContactListRow extends StatelessWidget {
  const _ContactListRow({required this.item, required this.onTap});

  final ContactListItemState item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final toneColor = switch (item.badge.tone) {
      UiStatusTone.success => colors.success,
      UiStatusTone.warning => colors.warning,
      UiStatusTone.danger => colors.danger,
      UiStatusTone.info => colors.info,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.appRadii.md),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: spacing.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: 0.72)),
            ),
          ),
          child: Row(
            children: [
              AppAvatar(label: item.user.displayName, radius: 24),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      item.subtitle.isEmpty
                          ? item.deviceSummary
                          : item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                    ),
                    SizedBox(height: spacing.xs),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: toneColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: spacing.xs),
                        Flexible(
                          child: Text(
                            item.badge.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: toneColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              Icon(
                item.isCurrentUser
                    ? Icons.person_outline_rounded
                    : item.hasExistingConversation
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.chevron_right_rounded,
                size: item.hasExistingConversation ? 19 : 22,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

class _FilterOption<T> {
  const _FilterOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _FilterStrip<T> extends StatelessWidget {
  const _FilterStrip({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<_FilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < options.length; index++) ...[
            ChoiceChip(
              label: Text(options[index].label),
              selected: options[index].value == selected,
              onSelected: (_) => onSelected(options[index].value),
              showCheckmark: false,
              selectedColor: colors.primary,
              backgroundColor: colors.surfaceMuted,
              side: BorderSide(
                color: options[index].value == selected
                    ? colors.primary
                    : colors.border,
              ),
              labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: options[index].value == selected
                    ? Colors.white
                    : colors.textMuted,
                fontWeight: FontWeight.w700,
              ),
              padding: EdgeInsets.symmetric(horizontal: spacing.sm),
            ),
            if (index < options.length - 1) SizedBox(width: spacing.sm),
          ],
        ],
      ),
    );
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
      appBar: AppBar(title: const Text('Contact details')),
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
