part of 'chat_list_page.dart';

// Extensions keep the page library cohesive while this file owns controller
// side effects that were previously mixed into the widget declaration.
// ignore_for_file: invalid_use_of_protected_member

extension _ChatListNavigationActions on _ChatListPageState {
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
    String avatarUrl = '',
    String roleLabel = '',
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          currentUserId: widget.sessionController.sessionUser!.id,
          conversation: conversation,
          title: title,
          avatarUrl: avatarUrl,
          roleLabel: roleLabel,
          chatFacade: widget.chatFacade,
          cryptoCoreFacade: widget.cryptoCoreFacade,
          database: widget.database,
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
      avatarUrl: item.avatarUrl,
      roleLabel: item.roleLabel,
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
        avatarUrl: user.avatarUrl,
        roleLabel: user.roleLabel,
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
                  title: Text(
                    item.isPinned ? 'Chatni bo‘shatish' : 'Chatni mahkamlash',
                  ),
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
                    item.isArchived ? 'Arxivdan chiqarish' : 'Arxivlash',
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
                    item.isUnread ? 'O‘qilgan qilish' : 'O‘qilmagan qilish',
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
                    'Kontakt kaliti tasdiqlandi.',
                    tone: AppStatusTone.success,
                );
              }
              : null,
        ),
      ),
    );
  }
}
