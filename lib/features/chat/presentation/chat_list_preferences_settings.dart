part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListPreferencesSettings on _ChatListPageState {
  Widget _buildNotificationsSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Bildirishnomalar',
        subtitle: 'Bu sozlamalar akkauntingiz bilan sinxronlanadi.',
      ),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notificationsEnabled,
              title: const Text('Bildirishnomalar'),
              onChanged: (value) =>
                  _setAccountBool('notifications_enabled', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notificationPreviewsEnabled,
              title: const Text('Bildirishnoma matni'),
              subtitle: const Text('Ogohlantirishda xabar matnini ko‘rsatish.'),
              onChanged: (value) =>
                  _setAccountBool('notification_previews', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _readReceiptsEnabled,
              title: const Text('O‘qilganlik belgisi'),
              onChanged: (value) =>
                  _setAccountBool('read_receipts_enabled', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _typingIndicatorsEnabled,
              title: const Text('Yozayotganlik belgisi'),
              onChanged: (value) =>
                  _setAccountBool('typing_indicators_enabled', value),
            ),
            _visibilitySetting(
              'Oxirgi faollik ko‘rinishi',
              _lastSeenVisibility,
              _setLastSeenVisibility,
            ),
            _visibilitySetting(
              'Onlayn holati ko‘rinishi',
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
          title: Text('Xabar mazmuni'),
          subtitle: Text(
            'Xabar mazmuni boshidan oxirigacha shifrlanadi va server uni o‘qiy olmaydi.',
          ),
        ),
      ),
    ]);
  }

  Widget _buildAppearanceSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      AppSectionHeader(
        title: context.antiQText(
          uz: 'Ko‘rinish va chatlar',
          en: 'Appearance & Chats',
        ),
        subtitle: context.antiQText(
          uz: 'Ko‘rinish va xabar yozishning mahalliy sozlamalari.',
          en: 'Local display and composer preferences.',
        ),
      ),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language_rounded),
              title: Text(
                context.antiQText(uz: 'Dastur tili', en: 'App language'),
              ),
              subtitle: Text(
                context.antiQText(
                  uz: 'Interfeys tilini tanlang.',
                  en: 'Choose the interface language.',
                ),
              ),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<AppLanguagePreference>(
                  value: widget.themeController.languagePreference,
                  items: const [
                    DropdownMenuItem(
                      value: AppLanguagePreference.uzbek,
                      child: Text('O‘zbekcha'),
                    ),
                    DropdownMenuItem(
                      value: AppLanguagePreference.english,
                      child: Text('English'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.themeController.setLanguage(value);
                    }
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.themeController.themeMode == ThemeMode.dark,
              title: Text(
                context.antiQText(uz: 'Qorong‘i rejim', en: 'Dark mode'),
              ),
              onChanged: (value) => widget.themeController.setThemeMode(
                value ? ThemeMode.dark : ThemeMode.light,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.appPreferences.showArchivedByDefault,
              title: Text(
                context.antiQText(
                  uz: 'Arxivlangan chatlarni ko‘rsatish',
                  en: 'Show archived chats',
                ),
              ),
              onChanged: (value) => _controller.updateAppPreferences(
                state.appPreferences.copyWith(showArchivedByDefault: value),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.appPreferences.keepDrafts,
              title: Text(
                context.antiQText(
                  uz: 'Qoralamalarni saqlash',
                  en: 'Keep drafts',
                ),
              ),
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
    const AppSectionHeader(title: 'Dastur va yordam'),
    SizedBox(height: context.appSpacing.sm),
    AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Versiya', state.appVersion),
          _buildInfoRow('Yordam', state.supportEmail),
          _buildInfoRow('API', state.apiBaseUrl),
        ],
      ),
    ),
  ]);
}
