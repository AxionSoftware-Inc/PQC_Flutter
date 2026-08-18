part of 'chat_hub_controller.dart';

// Projection members implement the contract declared by the base controller.
// ignore_for_file: annotate_overrides

mixin _ChatHubProjection on _ChatHubControllerBase {
  SettingsViewState get settingsState {
    final sessionUser = sessionUserProvider();
    final currentUser = _users
        .where((item) => item.id == sessionUser.id)
        .firstOrNull;
    final currentDevice = currentUser?.devices
        .where((item) => item.deviceId == sessionUser.deviceId)
        .firstOrNull;
    return SettingsViewState(
      sessionUser: sessionUser,
      currentWorkspace: _findCurrentWorkspace(sessionUser),
      currentUser: currentUser,
      currentDevice: currentDevice,
      devices: currentUser?.devices ?? const [],
      security: _securityState,
      backup: _backupState,
      appPreferences: _appPreferences,
      appVersion: const String.fromEnvironment(
        'APP_VERSION',
        defaultValue: '1.0.0+1',
      ),
      appSkinId: const String.fromEnvironment(
        'APP_SKIN',
        defaultValue: 'default',
      ),
      apiBaseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://91.108.121.56/api',
      ),
      supportEmail: const String.fromEnvironment(
        'SUPPORT_EMAIL',
        defaultValue: 'support@pqc-chat.local',
      ),
    );
  }

  Future<List<ConversationListItemState>> _buildConversationItems(
    SessionUser sessionUser,
  ) async {
    final rows = await database.readConversations();
    final rowMap = {
      for (final row in rows)
        if (row.workspaceId == sessionUser.activeWorkspaceId ||
            row.workspaceId == 0)
          row.id: row,
    };
    final draftMap = <int, String>{};
    final localPreviewMap = <int, String>{};
    final messageStateMap = <int, MessageDeliveryState?>{};
    for (final conversation in _conversations) {
      final draft = await database.readDraft(conversation.id);
      if (draft != null && draft.draftText.trim().isNotEmpty) {
        draftMap[conversation.id] = draft.draftText.trim();
      }
      final messages = await database.readMessagesForConversation(
        conversation.id,
      );
      if (messages.isNotEmpty) {
        final latest = messages.last;
        final body = latest.plaintextBody.trim();
        if (body.isNotEmpty &&
            !body.startsWith('[decrypt-') &&
            !body.contains('Historical decrypt unavailable')) {
          localPreviewMap[conversation.id] = body;
        }
        if (latest.senderId == currentUserId) {
          messageStateMap[conversation.id] = _deliveryStateFromStored(
            latest.deliveryState,
          );
        }
      }
    }

    final items = _conversations
        .map((conversation) {
          final peerId = conversation.participantIds.firstWhere(
            (id) => id != currentUserId,
            orElse: () => -1,
          );
          final peerUser = _users
              .where((user) => user.id == peerId)
              .firstOrNull;
          final trust = peerUser == null ? null : _trustByUserId[peerUser.id];
          final draftPreview = draftMap[conversation.id];
          final row = rowMap[conversation.id];
          final unreadCount = row?.unreadCount ?? conversation.unreadCount;
          final archived = _chatPreferences.archivedConversationIds.contains(
            conversation.id,
          );
          final manuallyUnread = _chatPreferences.manuallyUnreadConversationIds
              .contains(conversation.id);
          return ConversationListItemState(
            conversation: conversation,
            title: conversation.isGroup
                ? conversation.title
                : (peerUser?.displayName.isNotEmpty == true
                      ? peerUser!.displayName
                      : conversation.title),
            preview: draftPreview != null && _appPreferences.keepDrafts
                ? 'Draft: $draftPreview'
                : localPreviewMap[conversation.id] ??
                      conversation.lastMessagePreview,
            draftPreview: draftPreview,
            unreadCount: unreadCount,
            isPinned: _chatPreferences.pinnedConversationIds.contains(
              conversation.id,
            ),
            isArchived: archived,
            isManuallyUnread: manuallyUnread,
            updatedAt: conversation.updatedAt,
            deliveryState: messageStateMap[conversation.id],
            trustBadge: conversation.isGroup
                ? const ContactTrustBadgeState(
                    label: 'Encrypted',
                    tone: UiStatusTone.info,
                  )
                : trust == null
                ? null
                : _badgeForTrust(trust),
            deviceSummary: conversation.isGroup
                ? 'Workspace encrypted'
                : _deviceSummaryForUser(peerUser),
            avatarUrl: conversation.isGroup ? '' : peerUser?.avatarUrl ?? '',
            roleLabel: conversation.isGroup ? '' : peerUser?.roleLabel ?? '',
          );
        })
        .where(_matchesConversationFilter)
        .toList();

    items.sort((a, b) {
      final pinnedA = a.isPinned ? 1 : 0;
      final pinnedB = b.isPinned ? 1 : 0;
      if (pinnedA != pinnedB) {
        return pinnedB.compareTo(pinnedA);
      }
      if (a.isUnread != b.isUnread) {
        return a.isUnread ? -1 : 1;
      }
      if (a.hasDraft != b.hasDraft) {
        return a.hasDraft ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return items;
  }

  bool _matchesConversationFilter(ConversationListItemState item) {
    final query = _chatPreferences.searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      final haystack = '${item.title} ${item.preview} ${item.deviceSummary}'
          .toLowerCase();
      if (!haystack.contains(query)) {
        return false;
      }
    }

    final selectedFilter = _chatPreferences.selectedFilter;
    if (selectedFilter == ChatListFilter.archived) {
      return item.isArchived;
    }
    if (selectedFilter != ChatListFilter.archived && item.isArchived) {
      return _appPreferences.showArchivedByDefault &&
          selectedFilter == ChatListFilter.all;
    }
    switch (selectedFilter) {
      case ChatListFilter.unread:
        return item.isUnread;
      case ChatListFilter.pinned:
        return item.isPinned;
      case ChatListFilter.archived:
        return item.isArchived;
      case ChatListFilter.all:
        return true;
    }
  }
}
