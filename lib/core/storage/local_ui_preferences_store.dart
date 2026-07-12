import 'package:shared_preferences/shared_preferences.dart';

enum ChatListFilter { all, unread, pinned, archived }
enum AppThemePreference { light, dark }

class ChatListPreferences {
  const ChatListPreferences({
    this.searchQuery = '',
    this.selectedFilter = ChatListFilter.all,
    this.pinnedConversationIds = const <int>{},
    this.archivedConversationIds = const <int>{},
    this.manuallyUnreadConversationIds = const <int>{},
  });

  final String searchQuery;
  final ChatListFilter selectedFilter;
  final Set<int> pinnedConversationIds;
  final Set<int> archivedConversationIds;
  final Set<int> manuallyUnreadConversationIds;

  ChatListPreferences copyWith({
    String? searchQuery,
    ChatListFilter? selectedFilter,
    Set<int>? pinnedConversationIds,
    Set<int>? archivedConversationIds,
    Set<int>? manuallyUnreadConversationIds,
  }) {
    return ChatListPreferences(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedFilter: selectedFilter ?? this.selectedFilter,
      pinnedConversationIds:
          pinnedConversationIds ?? this.pinnedConversationIds,
      archivedConversationIds:
          archivedConversationIds ?? this.archivedConversationIds,
      manuallyUnreadConversationIds:
          manuallyUnreadConversationIds ?? this.manuallyUnreadConversationIds,
    );
  }
}

class AppPreferencesState {
  const AppPreferencesState({
    this.showArchivedByDefault = false,
    this.compactListMode = false,
    this.keepDrafts = true,
    this.preferManualRefreshHints = false,
    this.themePreference = AppThemePreference.light,
  });

  final bool showArchivedByDefault;
  final bool compactListMode;
  final bool keepDrafts;
  final bool preferManualRefreshHints;
  final AppThemePreference themePreference;

  AppPreferencesState copyWith({
    bool? showArchivedByDefault,
    bool? compactListMode,
    bool? keepDrafts,
    bool? preferManualRefreshHints,
    AppThemePreference? themePreference,
  }) {
    return AppPreferencesState(
      showArchivedByDefault:
          showArchivedByDefault ?? this.showArchivedByDefault,
      compactListMode: compactListMode ?? this.compactListMode,
      keepDrafts: keepDrafts ?? this.keepDrafts,
      preferManualRefreshHints:
          preferManualRefreshHints ?? this.preferManualRefreshHints,
      themePreference: themePreference ?? this.themePreference,
    );
  }
}

class LocalUiPreferencesStore {
  static const _chatSearchPrefix = 'ui_chat_search';
  static const _chatFilterPrefix = 'ui_chat_filter';
  static const _chatPinnedPrefix = 'ui_chat_pinned';
  static const _chatArchivedPrefix = 'ui_chat_archived';
  static const _chatManualUnreadPrefix = 'ui_chat_manual_unread';
  static const _showArchivedByDefaultKey = 'ui_pref_show_archived';
  static const _compactListModeKey = 'ui_pref_compact_list';
  static const _keepDraftsKey = 'ui_pref_keep_drafts';
  static const _preferManualRefreshHintsKey = 'ui_pref_manual_refresh_hints';
  static const _themePreferenceKey = 'ui_pref_theme_preference';

  Future<ChatListPreferences> readChatListPreferences({
    required int accountId,
    required int workspaceId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final scope = _scope(accountId: accountId, workspaceId: workspaceId);
    final filterName =
        preferences.getString('$_chatFilterPrefix:$scope') ??
        ChatListFilter.all.name;
    return ChatListPreferences(
      searchQuery: preferences.getString('$_chatSearchPrefix:$scope') ?? '',
      selectedFilter: ChatListFilter.values.firstWhere(
        (item) => item.name == filterName,
        orElse: () => ChatListFilter.all,
      ),
      pinnedConversationIds: _readIntSet(
        preferences,
        '$_chatPinnedPrefix:$scope',
      ),
      archivedConversationIds: _readIntSet(
        preferences,
        '$_chatArchivedPrefix:$scope',
      ),
      manuallyUnreadConversationIds: _readIntSet(
        preferences,
        '$_chatManualUnreadPrefix:$scope',
      ),
    );
  }

  Future<void> writeChatListPreferences({
    required int accountId,
    required int workspaceId,
    required ChatListPreferences preferencesState,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final scope = _scope(accountId: accountId, workspaceId: workspaceId);
    await preferences.setString(
      '$_chatSearchPrefix:$scope',
      preferencesState.searchQuery,
    );
    await preferences.setString(
      '$_chatFilterPrefix:$scope',
      preferencesState.selectedFilter.name,
    );
    await _writeIntSet(
      preferences,
      '$_chatPinnedPrefix:$scope',
      preferencesState.pinnedConversationIds,
    );
    await _writeIntSet(
      preferences,
      '$_chatArchivedPrefix:$scope',
      preferencesState.archivedConversationIds,
    );
    await _writeIntSet(
      preferences,
      '$_chatManualUnreadPrefix:$scope',
      preferencesState.manuallyUnreadConversationIds,
    );
  }

  Future<AppPreferencesState> readAppPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    return AppPreferencesState(
      showArchivedByDefault:
          preferences.getBool(_showArchivedByDefaultKey) ?? false,
      compactListMode: preferences.getBool(_compactListModeKey) ?? false,
      keepDrafts: preferences.getBool(_keepDraftsKey) ?? true,
      preferManualRefreshHints:
          preferences.getBool(_preferManualRefreshHintsKey) ?? false,
      themePreference: AppThemePreference.values.firstWhere(
        (item) =>
            item.name ==
            (preferences.getString(_themePreferenceKey) ??
                AppThemePreference.light.name),
        orElse: () => AppThemePreference.light,
      ),
    );
  }

  Future<void> writeAppPreferences(AppPreferencesState state) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      _showArchivedByDefaultKey,
      state.showArchivedByDefault,
    );
    await preferences.setBool(_compactListModeKey, state.compactListMode);
    await preferences.setBool(_keepDraftsKey, state.keepDrafts);
    await preferences.setBool(
      _preferManualRefreshHintsKey,
      state.preferManualRefreshHints,
    );
    await preferences.setString(_themePreferenceKey, state.themePreference.name);
  }

  Set<int> _readIntSet(SharedPreferences preferences, String key) {
    return (preferences.getStringList(key) ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  Future<void> _writeIntSet(
    SharedPreferences preferences,
    String key,
    Set<int> values,
  ) {
    return preferences.setStringList(
      key,
      values.map((item) => '$item').toList()..sort(),
    );
  }

  String _scope({required int accountId, required int workspaceId}) {
    return '$accountId:$workspaceId';
  }
}
