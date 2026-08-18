part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListStateViews on _ChatListPageState {
  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.appSpacing;
    final sessionUser = widget.sessionController.sessionUser!;
    final chatState = _controller.chatState;
    final contactsState = _controller.contactsState;
    final settingsState = _controller.settingsState;
    final tabs = [
      _TabMeta(
        label: context.antiQText(uz: 'Chatlar', en: 'Chats'),
        icon: HugeIcons.strokeRoundedChat,
        title:
            settingsState.currentWorkspace?.name ??
            context.antiQText(uz: 'Chatlar', en: 'Chats'),
      ),
      _TabMeta(
        label: context.antiQText(uz: 'Kontaktlar', en: 'Contacts'),
        icon: HugeIcons.strokeRoundedContactBook,
        title: context.antiQText(uz: 'Kontaktlar', en: 'Contacts'),
      ),
      if (_taskKpiModuleEnabled)
        _TabMeta(
          label: context.antiQText(uz: 'Vazifalar', en: 'Tasks'),
          icon: HugeIcons.strokeRoundedTask01,
          title: context.antiQText(uz: 'Vazifalar', en: 'Tasks'),
        ),
      _TabMeta(
        label: context.antiQText(uz: 'Sozlamalar', en: 'Settings'),
        icon: HugeIcons.strokeRoundedSettings02,
        title: context.antiQText(uz: 'Sozlamalar', en: 'Settings'),
      ),
      if (_showAdminTab)
        _TabMeta(
          label: context.antiQText(uz: 'Admin', en: 'Admin'),
          icon: HugeIcons.strokeRoundedShieldUser,
          title: context.antiQText(uz: 'Admin panel', en: 'Admin panel'),
        ),
    ];

    return AppScaffold(
      scaffoldKey: _scaffoldKey,
      drawer: _buildNavigationDrawer(settingsState),
      appBar: AppBar(
        toolbarHeight: 56,
        leadingWidth: 52,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: _PremiumIconButton(
            tooltip: context.antiQText(uz: 'Menyu', en: 'Menu'),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: Icons.menu_rounded,
          ),
        ),
        title: Text(
          tabs[_selectedTabIndex].title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _openProfile(settingsState),
              child: AppAvatar(
                label: sessionUser.displayName,
                imageUrl: sessionUser.avatarUrl,
                radius: 17,
              ),
            ),
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
                  if (_taskKpiModuleEnabled)
                    TaskKpiPage(
                      repository: widget.taskKpiRepository,
                      currentUserId: sessionUser.id,
                    ),
                  RefreshIndicator(
                    onRefresh: _refresh,
                    child: _buildSettingsOverview(settingsState),
                  ),
                  if (_showAdminTab)
                    AdminPanelPage(
                      repository: widget.rbacRepository,
                      standalone: false,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(
          spacing.md,
          spacing.xs,
          spacing.md,
          spacing.sm,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.appColors.surface.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(context.appRadii.xl),
            border: Border.all(
              color: context.appColors.border.withValues(alpha: 0.72),
            ),
            boxShadow: context.appShadows.floating,
          ),
          child: _PremiumBottomNavigation(
            tabs: tabs,
            selectedIndex: _selectedTabIndex,
            onSelected: (index) => setState(() => _selectedTabIndex = index),
          ),
        ),
      ),
    );
  }
}
