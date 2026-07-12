import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/storage/local_ui_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('chat list preferences persist by account and workspace scope', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalUiPreferencesStore();

    await store.writeChatListPreferences(
      accountId: 7,
      workspaceId: 3,
      preferencesState: const ChatListPreferences(
        searchQuery: 'atlas',
        selectedFilter: ChatListFilter.pinned,
        pinnedConversationIds: {1, 2},
        archivedConversationIds: {9},
        manuallyUnreadConversationIds: {4},
      ),
    );

    final restored = await store.readChatListPreferences(
      accountId: 7,
      workspaceId: 3,
    );

    expect(restored.searchQuery, 'atlas');
    expect(restored.selectedFilter, ChatListFilter.pinned);
    expect(restored.pinnedConversationIds, {1, 2});
    expect(restored.archivedConversationIds, {9});
    expect(restored.manuallyUnreadConversationIds, {4});
  });

  test('app preferences roundtrip works', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalUiPreferencesStore();

    await store.writeAppPreferences(
      const AppPreferencesState(
        showArchivedByDefault: true,
        compactListMode: true,
        keepDrafts: false,
        preferManualRefreshHints: true,
      ),
    );

    final restored = await store.readAppPreferences();

    expect(restored.showArchivedByDefault, isTrue);
    expect(restored.compactListMode, isTrue);
    expect(restored.keepDrafts, isFalse);
    expect(restored.preferManualRefreshHints, isTrue);
  });
}
