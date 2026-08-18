part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListAccountSettings on _ChatListPageState {
  Widget _buildAccountSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    final session = state.sessionUser;
    return _settingsList([
      AppSurfaceCard(
        backgroundColor: context.appColors.primarySoft,
        child: Column(
          children: [
            AppAvatar(
              label: session.displayName,
              imageUrl: session.avatarUrl,
              radius: 38,
            ),
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
            SizedBox(height: spacing.sm),
            TextButton.icon(
              onPressed: _showEditProfile,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Profilni tahrirlash'),
            ),
          ],
        ),
      ),
      SizedBox(height: spacing.lg),
      const AppSectionHeader(title: 'Ish maydoni'),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          children: [
            _buildInfoRow(
              'Joriy',
              state.currentWorkspace?.name ?? 'Mavjud emas',
            ),
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
              title: const Text('Akkauntdan chiqish'),
              subtitle: const Text('Bu qurilma ro‘yxatda qoladi.'),
              onTap: () => _logout(forgetDevice: false),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: context.appColors.danger,
              ),
              title: const Text('Bu qurilmani unutish'),
              subtitle: const Text(
                'Mahalliy seans va mahalliy tarix o‘chiriladi.',
              ),
              onTap: () => _logout(forgetDevice: true),
            ),
          ],
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
          DropdownMenuItem(value: 'everyone', child: Text('Hamma')),
          DropdownMenuItem(value: 'contacts', child: Text('Kontaktlar')),
          DropdownMenuItem(value: 'nobody', child: Text('Hech kim')),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    ),
  );

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
}
