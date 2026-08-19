part of 'chat_list_page.dart';

// Extensions keep the page library cohesive while this file owns controller
// side effects that were previously mixed into the widget declaration.
// ignore_for_file: invalid_use_of_protected_member

extension _ChatListStateActions on _ChatListPageState {
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

  Future<void> _loadAdminAccess() async {
    try {
      final result = await widget.rbacRepository.getCurrentAccess();
      if (!mounted) return;
      setState(() {
        _isWorkspaceAdmin =
            result is Map<String, dynamic> && result['is_admin'] == true;
      });
    } catch (_) {
      if (mounted) setState(() => _isWorkspaceAdmin = false);
    }
  }
}
