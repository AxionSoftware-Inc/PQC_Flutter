part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListSettingsViews on _ChatListPageState {
  Widget _buildNavigationDrawer(SettingsViewState state) {
    final session = state.sessionUser;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: context.appColors.primarySoft),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAvatar(
                    label: session.displayName,
                    imageUrl: session.avatarUrl,
                    radius: 28,
                  ),
                  const Spacer(),
                  Text(
                    session.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    session.username,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (state.currentUser?.roleLabel.isNotEmpty == true)
                    Text(
                      state.currentUser!.roleLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.appColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedChat,
                size: 21,
              ),
              title: Text(context.antiQText(uz: 'Chatlar', en: 'Chats')),
              onTap: () {
                _scaffoldKey.currentState?.closeDrawer();
                setState(() => _selectedTabIndex = 0);
              },
            ),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedContactBook,
                size: 21,
              ),
              title: Text(context.antiQText(uz: 'Kontaktlar', en: 'Contacts')),
              onTap: () {
                _scaffoldKey.currentState?.closeDrawer();
                setState(() => _selectedTabIndex = 1);
              },
            ),
            if (_taskKpiModuleEnabled)
              ListTile(
                leading: const HugeIcon(
                  icon: HugeIcons.strokeRoundedTask01,
                  size: 21,
                ),
                title: Text(context.antiQText(uz: 'Vazifalar', en: 'Tasks')),
                onTap: () {
                  _scaffoldKey.currentState?.closeDrawer();
                  setState(() => _selectedTabIndex = _taskKpiTabIndex);
                },
              ),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedSettings02,
                size: 21,
              ),
              title: Text(context.antiQText(uz: 'Sozlamalar', en: 'Settings')),
              onTap: () {
                _scaffoldKey.currentState?.closeDrawer();
                setState(() => _selectedTabIndex = _settingsTabIndex);
              },
            ),
            if (_showAdminTab)
              ListTile(
                leading: const HugeIcon(
                  icon: HugeIcons.strokeRoundedShieldUser,
                  size: 21,
                ),
                title: Text(
                  context.antiQText(uz: 'Admin panel', en: 'Admin panel'),
                ),
                onTap: () {
                  _scaffoldKey.currentState?.closeDrawer();
                  setState(() => _selectedTabIndex = _adminTabIndex);
                },
              ),
            const Divider(),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedUserCircle,
                size: 21,
              ),
              title: Text(context.antiQText(uz: 'Profil', en: 'Profile')),
              onTap: () {
                _scaffoldKey.currentState?.closeDrawer();
                _openProfile(state);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: Text(context.antiQText(uz: 'Chiqish', en: 'Log out')),
              onTap: () async {
                _scaffoldKey.currentState?.closeDrawer();
                await _logout(forgetDevice: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountTab(SettingsViewState state) {
    final spacing = context.appSpacing;
    final session = state.sessionUser;
    return ListView(
      padding: EdgeInsets.all(spacing.md),
      children: [
        AppSurfaceCard(
          backgroundColor: context.appColors.primarySoft,
          child: Column(
            children: [
              AppAvatar(
                label: session.displayName,
                imageUrl: session.avatarUrl,
                radius: 36,
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
              if (state.currentUser?.roleLabel.isNotEmpty == true) ...[
                SizedBox(height: spacing.xs),
                AppBadge(
                  label: state.currentUser!.roleLabel,
                  tone: AppStatusTone.info,
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: spacing.md),
        AppSurfaceCard(
          child: Column(
            children: [
              _buildInfoRow(
                'Ish maydoni',
                state.currentWorkspace?.name ?? 'Mavjud emas',
              ),
              _buildInfoRow('Qurilma', session.deviceId),
            ],
          ),
        ),
        SizedBox(height: spacing.md),
        AppPrimaryButton(
          onPressed: _showEditProfile,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Profilni tahrirlash'),
        ),
      ],
    );
  }

  Widget _buildSettingsOverview(SettingsViewState state) {
    final spacing = context.appSpacing;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.xs,
        spacing.md,
        spacing.md,
      ),
      children: [
        AppSectionHeader(
          title: context.antiQText(uz: 'Sozlamalar', en: 'Settings'),
          subtitle: context.antiQText(
            uz: 'Kerakli bo‘limni tanlang.',
            en: 'Choose a section.',
          ),
        ),
        SizedBox(height: spacing.xs),
        _settingsSection(
          context.antiQText(uz: 'Akkaunt', en: 'Account'),
          context.antiQText(
            uz: 'Profil, ish maydoni va seans',
            en: 'Profile, workspace and session',
          ),
          Icons.person_outline_rounded,
          _buildAccountSettings,
        ),
        _settingsSection(
          context.antiQText(uz: 'Xavfsizlik', en: 'Security'),
          context.antiQText(
            uz: 'Ishonch, kalitlar va shifrni ochish holati',
            en: 'Trust, keys and decryption health',
          ),
          Icons.shield_outlined,
          _buildSecuritySettings,
        ),
        _settingsSection(
          context.antiQText(uz: 'Qurilmalar', en: 'Devices'),
          context.antiQText(
            uz: 'Ro‘yxatdagi qurilmalar va bekor qilish',
            en: 'Registered devices and revoke',
          ),
          Icons.devices_outlined,
          _buildDevicesSettings,
        ),
        _settingsSection(
          context.antiQText(uz: 'Zaxira va tiklash', en: 'Backup & Recovery'),
          context.antiQText(
            uz: 'Tiklash va ko‘chma shifrlangan zaxiralar',
            en: 'Restore and portable encrypted backups',
          ),
          Icons.backup_outlined,
          _buildBackupSettings,
        ),
        _settingsSection(
          context.antiQText(
            uz: 'Bildirishnomalar va maxfiylik',
            en: 'Notifications & Privacy',
          ),
          context.antiQText(
            uz: 'Ogohlantirishlar, yozish va faollik',
            en: 'Alerts, typing and presence',
          ),
          Icons.notifications_outlined,
          _buildNotificationsSettings,
        ),
        _settingsSection(
          context.antiQText(
            uz: 'Ko‘rinish va chatlar',
            en: 'Appearance & Chats',
          ),
          context.antiQText(
            uz: 'Mavzu, qoralamalar va chatlar joylashuvi',
            en: 'Theme, drafts and inbox layout',
          ),
          Icons.palette_outlined,
          _buildAppearanceSettings,
        ),
        _settingsSection(
          context.antiQText(uz: 'Dastur va yordam', en: 'About & Support'),
          context.antiQText(
            uz: 'Versiya va yordam tafsilotlari',
            en: 'Version and support details',
          ),
          Icons.info_outline_rounded,
          _buildAboutSettings,
        ),
      ],
    );
  }
}
