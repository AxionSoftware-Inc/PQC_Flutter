part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListContactViews on _ChatListPageState {
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
          hintText: context.antiQText(
            uz: 'Kontaktlarni qidiring',
            en: 'Search contacts',
          ),
          onChanged: _controller.setContactsSearchQuery,
        ),
        SizedBox(height: spacing.md),
        _buildContactsFilterSelector(state.selectedFilter),
        SizedBox(height: spacing.lg),
        if (_controller.isLoading && state.sections.isEmpty)
          ..._buildContactSkeleton()
        else if (state.sections.isEmpty)
          _buildEmptyCard(
            context.antiQText(
              uz: 'Bu filtr bo‘yicha kontakt topilmadi.',
              en: 'No contacts match this filter.',
            ),
          )
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

  Widget _buildContactsFilterSelector(ContactsTrustFilter filter) {
    return _FilterStrip<ContactsTrustFilter>(
      selected: filter,
      options: const [
        _FilterOption(value: ContactsTrustFilter.all, label: 'Barchasi'),
        _FilterOption(
          value: ContactsTrustFilter.verified,
          label: 'Tasdiqlangan',
        ),
        _FilterOption(
          value: ContactsTrustFilter.needsAttention,
          label: 'E’tibor kerak',
        ),
        _FilterOption(
          value: ContactsTrustFilter.notReady,
          label: 'Tayyor emas',
        ),
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
        return context.antiQText(
          uz: 'O‘qilmagan chat topilmadi.',
          en: 'No unread chats.',
        );
      case ChatListFilter.pinned:
        return context.antiQText(
          uz: 'Mahkamlangan chatlar hali yo‘q.',
          en: 'No pinned chats yet.',
        );
      case ChatListFilter.archived:
        return context.antiQText(
          uz: 'Arxivlangan chatlar hali yo‘q.',
          en: 'No archived chats.',
        );
      case ChatListFilter.all:
        return context.antiQText(
          uz: 'Hali chatlar yo‘q. Kontaktlar bo‘limidan suhbat boshlashingiz mumkin.',
          en: 'No chats yet. Start a conversation from Contacts.',
        );
    }
  }

  String _formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final local = time.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final dayDifference = today.difference(messageDay).inDays;
    if (dayDifference <= 0) {
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    if (dayDifference == 1) {
      return context.antiQText(uz: 'Kecha', en: 'Yesterday');
    }
    if (dayDifference < 7) {
      const weekdays = ['Du', 'Se', 'Cho', 'Pa', 'Ju', 'Sha', 'Ya'];
      return weekdays[local.weekday - 1];
    }
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
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
