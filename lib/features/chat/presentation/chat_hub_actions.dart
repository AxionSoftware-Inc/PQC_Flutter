part of 'chat_hub_controller.dart';

mixin _ChatHubActions on _ChatHubControllerBase {
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _loadCoreState();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _error = null;
    try {
      await _loadCoreState();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _loadCoreState() async {
    final sessionUser = sessionUserProvider();
    _appPreferences = await _preferencesStore.readAppPreferences();
    _chatPreferences = await _preferencesStore.readChatListPreferences(
      accountId: sessionUser.accountId,
      workspaceId: sessionUser.activeWorkspaceId,
    );
    try {
      final response = await accountRepository.get('/users/me/settings');
      if (response is Map) {
        _accountSettings = Map<String, dynamic>.from(response);
      }
    } catch (_) {
      // Account settings must not block the inbox while offline.
    }
    final state = await chatFacade.loadChatList(currentUserId: currentUserId);
    _users = state.users;
    _conversations = state.conversations;
    _trustByUserId = state.trustByUserId;
    final historical = await cryptoCoreFacade.historicalDecryptCheck();
    _securityState = _buildSecurityState(
      users: _users,
      trustByUserId: _trustByUserId,
      sessionUser: sessionUser,
      historical: historical,
    );
    _conversationItems = await _buildConversationItems(sessionUser);
    _contactSections = _buildContactSections(sessionUser);
  }

  Future<Conversation> startChatForUser(AppUser user) async {
    final existing = _findPrivateConversation(user.id);
    if (existing != null) {
      return existing;
    }
    final conversation = await chatFacade.openPrivateConversation(user.id);
    await refresh();
    return conversation;
  }

  ContactDetailState buildContactDetailState(AppUser user) {
    return ContactDetailState(
      user: user,
      badge: _buildContactBadge(user),
      deviceSummary: _deviceSummaryForUser(user),
      devices: user.devices,
      canVerify: user.id != currentUserId && user.preferredX25519Device != null,
      hasExistingConversation: _findPrivateConversation(user.id) != null,
    );
  }

  Future<void> verifyContact(AppUser user) async {
    final conversation = await startChatForUser(user);
    await chatFacade.verifyConversationPeerKey(
      currentUserId: currentUserId,
      conversation: conversation,
    );
    await refresh();
  }

  Future<void> updateContactRole(AppUser user, String role) async {
    await chatFacade.updateUserRole(userId: user.id, role: role);
    await refresh();
  }

  Future<void> setChatSearchQuery(String value) async {
    _chatPreferences = _chatPreferences.copyWith(searchQuery: value);
    await _persistChatPreferences();
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  Future<void> setChatFilter(ChatListFilter filter) async {
    _chatPreferences = _chatPreferences.copyWith(selectedFilter: filter);
    await _persistChatPreferences();
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  Future<void> togglePinned(int conversationId) async {
    final next = {..._chatPreferences.pinnedConversationIds};
    if (!next.remove(conversationId)) {
      next.add(conversationId);
    }
    _chatPreferences = _chatPreferences.copyWith(pinnedConversationIds: next);
    await _persistChatPreferences();
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  Future<void> toggleArchived(int conversationId) async {
    final next = {..._chatPreferences.archivedConversationIds};
    if (!next.remove(conversationId)) {
      next.add(conversationId);
    }
    _chatPreferences = _chatPreferences.copyWith(archivedConversationIds: next);
    await _persistChatPreferences();
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  Future<void> toggleManualUnread(int conversationId) async {
    final next = {..._chatPreferences.manuallyUnreadConversationIds};
    if (!next.remove(conversationId)) {
      next.add(conversationId);
    }
    _chatPreferences = _chatPreferences.copyWith(
      manuallyUnreadConversationIds: next,
    );
    await _persistChatPreferences();
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  void setContactsSearchQuery(String value) {
    _contactsSearchQuery = value;
    _contactSections = _buildContactSections(sessionUserProvider());
    notifyListeners();
  }

  void setContactsFilter(ContactsTrustFilter filter) {
    _contactsFilter = filter;
    _contactSections = _buildContactSections(sessionUserProvider());
    notifyListeners();
  }

  Future<void> updateAppPreferences(AppPreferencesState state) async {
    _appPreferences = state;
    await _preferencesStore.writeAppPreferences(state);
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  Future<void> updateAccountSettings(Map<String, dynamic> values) async {
    final response = await accountRepository.patch(
      '/users/me/settings',
      values,
    );
    if (response is Map) {
      _accountSettings = Map<String, dynamic>.from(response);
      notifyListeners();
    }
  }

  Future<void> revokeDevice(String deviceId) async {
    await accountRepository.post(
      '/users/me/devices/$deviceId/revoke',
      const {},
    );
    await refresh();
  }

  Future<void> _persistChatPreferences() {
    final sessionUser = sessionUserProvider();
    return _preferencesStore.writeChatListPreferences(
      accountId: sessionUser.accountId,
      workspaceId: sessionUser.activeWorkspaceId,
      preferencesState: _chatPreferences,
    );
  }
}
