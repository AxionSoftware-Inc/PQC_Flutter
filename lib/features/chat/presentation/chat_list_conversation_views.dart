part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListConversationViews on _ChatListPageState {
  Widget _buildChatsTab(ChatListViewState state) {
    final spacing = context.appSpacing;
    final items = state.items;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.xs,
        spacing.md,
        spacing.md,
      ),
      children: [
        if (_selectedConversationIds.isNotEmpty) ...[
          AppSurfaceCard(
            backgroundColor: context.appColors.primarySoft,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Tanlovni bekor qilish',
                  onPressed: () => setState(_selectedConversationIds.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
                Expanded(
                  child: Text(
                    '${_selectedConversationIds.length} ta tanlandi',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Tanlanganlarni arxivlash',
                  onPressed: _archiveSelectedConversations,
                  icon: const Icon(Icons.archive_outlined),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.sm),
        ],
        _buildCompactChatToolbar(state.preferences.selectedFilter),
        SizedBox(height: spacing.sm),
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
                label: 'O‘qilmagan',
              ),
              secondaryBackground: _swipeActionBackground(
                alignment: Alignment.centerRight,
                color: context.appColors.warning,
                icon: item.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                label: item.isArchived ? 'Qaytarish' : 'Arxivlash',
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
                onAvatarLongPress: () =>
                    _toggleConversationSelection(item.conversation.id),
                onLongPress: () => _selectedConversationIds.isNotEmpty
                    ? _toggleConversationSelection(item.conversation.id)
                    : _showConversationActions(item),
                relativeTime: _formatRelativeTime(item.updatedAt),
              ),
            ),
      ],
    );
  }

  Widget _buildCompactChatToolbar(ChatListFilter selectedFilter) {
    final spacing = context.appSpacing;
    return Row(
      children: [
        Expanded(
          child: AppSearchField(
            controller: _chatSearchController,
            hintText: context.antiQText(uz: 'Qidirish', en: 'Search'),
            compact: true,
            onChanged: _controller.setChatSearchQuery,
          ),
        ),
        SizedBox(width: spacing.xs),
        PopupMenuButton<ChatListFilter>(
          tooltip: context.antiQText(uz: 'Chat filtri', en: 'Chat filter'),
          initialValue: selectedFilter,
          onSelected: _controller.setChatFilter,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: ChatListFilter.all,
              child: Text(context.antiQText(uz: 'Barchasi', en: 'All')),
            ),
            PopupMenuItem(
              value: ChatListFilter.unread,
              child: Text(context.antiQText(uz: 'O‘qilmagan', en: 'Unread')),
            ),
            PopupMenuItem(
              value: ChatListFilter.pinned,
              child: Text(context.antiQText(uz: 'Mahkamlangan', en: 'Pinned')),
            ),
            PopupMenuItem(
              value: ChatListFilter.archived,
              child: Text(context.antiQText(uz: 'Arxiv', en: 'Archived')),
            ),
          ],
          child: Container(
            height: 42,
            padding: EdgeInsets.symmetric(horizontal: spacing.sm),
            decoration: BoxDecoration(
              color: selectedFilter == ChatListFilter.all
                  ? context.appColors.surfaceMuted
                  : context.appColors.primarySoft,
              borderRadius: BorderRadius.circular(context.appRadii.md),
              border: Border.all(
                color: selectedFilter == ChatListFilter.all
                    ? context.appColors.border.withValues(alpha: 0.58)
                    : context.appColors.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: selectedFilter == ChatListFilter.all
                      ? context.appColors.textMuted
                      : context.appColors.primary,
                ),
                if (selectedFilter != ChatListFilter.all) ...[
                  SizedBox(width: spacing.xs),
                  Text(
                    _chatFilterShortLabel(selectedFilter),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.appColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _chatFilterShortLabel(ChatListFilter filter) => switch (filter) {
    ChatListFilter.all => context.antiQText(uz: 'Barchasi', en: 'All'),
    ChatListFilter.unread => context.antiQText(uz: 'Yangi', en: 'Unread'),
    ChatListFilter.pinned => context.antiQText(uz: 'Muhim', en: 'Pinned'),
    ChatListFilter.archived => context.antiQText(uz: 'Arxiv', en: 'Archived'),
  };

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
}
