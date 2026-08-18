part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListConversationActions on _ChatListPageState {
  void _toggleConversationSelection(int conversationId) {
    setState(() {
      if (!_selectedConversationIds.add(conversationId)) {
        _selectedConversationIds.remove(conversationId);
      }
    });
  }

  Future<void> _archiveSelectedConversations() async {
    final ids = List<int>.of(_selectedConversationIds);
    for (final id in ids) {
      await _controller.toggleArchived(id);
    }
    if (mounted) setState(_selectedConversationIds.clear);
  }
}
