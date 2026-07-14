import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/organization_context.dart';
import '../../../core/models/session_user.dart';
import '../../../core/storage/local_ui_preferences_store.dart';
import '../../../core/network/api_client.dart';
import '../../../core/config/api_config.dart';
import '../../chat/application/chat_facade.dart';
import '../../crypto/durability/crypto_core_facade.dart';
import '../../crypto/durability/crypto_durability_models.dart';
import '../../security/key_verification_service.dart';

enum ContactsTrustFilter { all, verified, needsAttention, notReady }

class ConversationListItemState {
  const ConversationListItemState({
    required this.conversation,
    required this.title,
    required this.preview,
    required this.updatedAt,
    this.draftPreview,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isArchived = false,
    this.isManuallyUnread = false,
    this.deliveryState,
    this.trustBadge,
    this.deviceSummary = '',
  });

  final Conversation conversation;
  final String title;
  final String preview;
  final String? draftPreview;
  final int unreadCount;
  final bool isPinned;
  final bool isArchived;
  final bool isManuallyUnread;
  final DateTime updatedAt;
  final MessageDeliveryState? deliveryState;
  final ContactTrustBadgeState? trustBadge;
  final String deviceSummary;

  bool get isUnread => unreadCount > 0 || isManuallyUnread;
  bool get hasDraft => draftPreview != null && draftPreview!.trim().isNotEmpty;
}

class ChatListViewState {
  const ChatListViewState({required this.preferences, required this.items});

  final ChatListPreferences preferences;
  final List<ConversationListItemState> items;
}

class ContactTrustBadgeState {
  const ContactTrustBadgeState({
    required this.label,
    required this.tone,
    this.details,
  });

  final String label;
  final UiStatusTone tone;
  final String? details;
}

class ContactListItemState {
  const ContactListItemState({
    required this.user,
    required this.title,
    required this.subtitle,
    required this.sortKey,
    required this.badge,
    required this.deviceSummary,
    required this.hasExistingConversation,
    this.privateConversation,
    this.isCurrentUser = false,
  });

  final AppUser user;
  final String title;
  final String subtitle;
  final String sortKey;
  final ContactTrustBadgeState badge;
  final String deviceSummary;
  final bool hasExistingConversation;
  final Conversation? privateConversation;
  final bool isCurrentUser;
}

class ContactsSectionState {
  const ContactsSectionState({required this.label, required this.items});

  final String label;
  final List<ContactListItemState> items;
}

class ContactsViewState {
  const ContactsViewState({
    required this.searchQuery,
    required this.selectedFilter,
    required this.sections,
  });

  final String searchQuery;
  final ContactsTrustFilter selectedFilter;
  final List<ContactsSectionState> sections;
}

class SecurityCenterState {
  const SecurityCenterState({
    required this.verifiedPeersCount,
    required this.needsAttentionCount,
    required this.notReadyCount,
    required this.isCurrentDeviceReady,
    required this.hasHistoricalDecryptCapability,
    required this.availableHistoricalKeysets,
  });

  final int verifiedPeersCount;
  final int needsAttentionCount;
  final int notReadyCount;
  final bool isCurrentDeviceReady;
  final bool hasHistoricalDecryptCapability;
  final int availableHistoricalKeysets;
}

class BackupRecoveryState {
  const BackupRecoveryState({
    this.lastExportedBlob,
    this.statusMessage,
    this.statusTone = UiStatusTone.info,
  });

  final String? lastExportedBlob;
  final String? statusMessage;
  final UiStatusTone statusTone;

  BackupRecoveryState copyWith({
    String? lastExportedBlob,
    String? statusMessage,
    UiStatusTone? statusTone,
  }) {
    return BackupRecoveryState(
      lastExportedBlob: lastExportedBlob ?? this.lastExportedBlob,
      statusMessage: statusMessage ?? this.statusMessage,
      statusTone: statusTone ?? this.statusTone,
    );
  }
}

class ContactDetailState {
  const ContactDetailState({
    required this.user,
    required this.badge,
    required this.deviceSummary,
    required this.devices,
    required this.canVerify,
    required this.hasExistingConversation,
  });

  final AppUser user;
  final ContactTrustBadgeState badge;
  final String deviceSummary;
  final List<AppUserDevice> devices;
  final bool canVerify;
  final bool hasExistingConversation;
}

class SettingsViewState {
  const SettingsViewState({
    required this.sessionUser,
    required this.currentWorkspace,
    required this.currentUser,
    required this.currentDevice,
    required this.devices,
    required this.security,
    required this.backup,
    required this.appPreferences,
    required this.appVersion,
    required this.appSkinId,
    required this.apiBaseUrl,
    required this.supportEmail,
  });

  final SessionUser sessionUser;
  final WorkspaceSummary? currentWorkspace;
  final AppUser? currentUser;
  final AppUserDevice? currentDevice;
  final List<AppUserDevice> devices;
  final SecurityCenterState security;
  final BackupRecoveryState backup;
  final AppPreferencesState appPreferences;
  final String appVersion;
  final String appSkinId;
  final String apiBaseUrl;
  final String supportEmail;
}

enum UiStatusTone { info, success, warning, danger }

class ChatHubController extends ChangeNotifier {
  ChatHubController({
    required this.chatFacade,
    required this.cryptoCoreFacade,
    required this.currentUserId,
    required this.sessionUserProvider,
    required this.apiClient,
    AppDatabase? database,
    LocalUiPreferencesStore? preferencesStore,
  }) : _database = database ?? AppDatabase(),
       _preferencesStore = preferencesStore ?? LocalUiPreferencesStore();

  final ChatFacade chatFacade;
  final CryptoCoreFacade cryptoCoreFacade;
  final int currentUserId;
  final SessionUser Function() sessionUserProvider;
  final ApiClient apiClient;
  final AppDatabase _database;
  final LocalUiPreferencesStore _preferencesStore;

  bool _isLoading = true;
  String? _error;
  String _contactsSearchQuery = '';
  ContactsTrustFilter _contactsFilter = ContactsTrustFilter.all;
  ChatListPreferences _chatPreferences = const ChatListPreferences();
  AppPreferencesState _appPreferences = const AppPreferencesState();
  BackupRecoveryState _backupState = const BackupRecoveryState();
  SecurityCenterState _securityState = const SecurityCenterState(
    verifiedPeersCount: 0,
    needsAttentionCount: 0,
    notReadyCount: 0,
    isCurrentDeviceReady: false,
    hasHistoricalDecryptCapability: false,
    availableHistoricalKeysets: 0,
  );
  List<AppUser> _users = const [];
  List<Conversation> _conversations = const [];
  Map<int, UserKeyTrust> _trustByUserId = const {};
  List<ConversationListItemState> _conversationItems = const [];
  List<ContactsSectionState> _contactSections = const [];
  String? _recoveryApprovalChallenge;

  bool get isLoading => _isLoading;
  String? get error => _error;
  ChatListViewState get chatState => ChatListViewState(
    preferences: _chatPreferences,
    items: _conversationItems,
  );
  ContactsViewState get contactsState => ContactsViewState(
    searchQuery: _contactsSearchQuery,
    selectedFilter: _contactsFilter,
    sections: _contactSections,
  );
  SettingsViewState get settingsState {
    final sessionUser = sessionUserProvider();
    final currentUser = _users
        .where((item) => item.id == sessionUser.id)
        .firstOrNull;
    final currentDevice = currentUser?.devices
        .where((item) => item.deviceId == sessionUser.deviceId)
        .firstOrNull;
    return SettingsViewState(
      sessionUser: sessionUser,
      currentWorkspace: _findCurrentWorkspace(sessionUser),
      currentUser: currentUser,
      currentDevice: currentDevice,
      devices: currentUser?.devices ?? const [],
      security: _securityState,
      backup: _backupState,
      appPreferences: _appPreferences,
      appVersion: const String.fromEnvironment(
        'APP_VERSION',
        defaultValue: '1.0.0+1',
      ),
      appSkinId: const String.fromEnvironment(
        'APP_SKIN',
        defaultValue: 'default',
      ),
      apiBaseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://91.108.121.56/api',
      ),
      supportEmail: const String.fromEnvironment(
        'SUPPORT_EMAIL',
        defaultValue: 'support@pqc-chat.local',
      ),
    );
  }

  Map<int, UserKeyTrust> get trustByUserId => _trustByUserId;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _loadCoreState();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _error = null;
    try {
      await _loadCoreState();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _loadCoreState() async {
    final sessionUser = sessionUserProvider();
    _appPreferences = await _preferencesStore.readAppPreferences();
    _chatPreferences = await _preferencesStore.readChatListPreferences(
      accountId: sessionUser.accountId,
      workspaceId: sessionUser.activeWorkspaceId,
    );
    final state = await chatFacade.loadChatList(currentUserId: currentUserId);
    _users = state.users;
    _conversations = state.conversations;
    _trustByUserId = state.trustByUserId;
    final historical = await cryptoCoreFacade.historicalDecryptCheck();
    _securityState = _buildSecurityState(
      users: _users,
      trustByUserId: _trustByUserId,
      sessionUser: sessionUser,
      historical: historical,
    );
    _conversationItems = await _buildConversationItems(sessionUser);
    _contactSections = _buildContactSections(sessionUser);
  }

  Future<Conversation> startChatForUser(AppUser user) async {
    final existing = _findPrivateConversation(user.id);
    if (existing != null) {
      return existing;
    }
    final conversation = await chatFacade.openPrivateConversation(user.id);
    await refresh();
    return conversation;
  }

  ContactDetailState buildContactDetailState(AppUser user) {
    return ContactDetailState(
      user: user,
      badge: _buildContactBadge(user),
      deviceSummary: _deviceSummaryForUser(user),
      devices: user.devices,
      canVerify: user.id != currentUserId && user.preferredX25519Device != null,
      hasExistingConversation: _findPrivateConversation(user.id) != null,
    );
  }

  Future<void> verifyContact(AppUser user) async {
    final conversation = await startChatForUser(user);
    await chatFacade.verifyConversationPeerKey(
      currentUserId: currentUserId,
      conversation: conversation,
    );
    await refresh();
  }

  Future<void> setChatSearchQuery(String value) async {
    _chatPreferences = _chatPreferences.copyWith(searchQuery: value);
    await _persistChatPreferences();
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  Future<void> setChatFilter(ChatListFilter filter) async {
    _chatPreferences = _chatPreferences.copyWith(selectedFilter: filter);
    await _persistChatPreferences();
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  Future<void> togglePinned(int conversationId) async {
    final next = {..._chatPreferences.pinnedConversationIds};
    if (!next.remove(conversationId)) {
      next.add(conversationId);
    }
    _chatPreferences = _chatPreferences.copyWith(pinnedConversationIds: next);
    await _persistChatPreferences();
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  Future<void> toggleArchived(int conversationId) async {
    final next = {..._chatPreferences.archivedConversationIds};
    if (!next.remove(conversationId)) {
      next.add(conversationId);
    }
    _chatPreferences = _chatPreferences.copyWith(archivedConversationIds: next);
    await _persistChatPreferences();
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  Future<void> toggleManualUnread(int conversationId) async {
    final next = {..._chatPreferences.manuallyUnreadConversationIds};
    if (!next.remove(conversationId)) {
      next.add(conversationId);
    }
    _chatPreferences = _chatPreferences.copyWith(
      manuallyUnreadConversationIds: next,
    );
    await _persistChatPreferences();
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  void setContactsSearchQuery(String value) {
    _contactsSearchQuery = value;
    _contactSections = _buildContactSections(sessionUserProvider());
    notifyListeners();
  }

  void setContactsFilter(ContactsTrustFilter filter) {
    _contactsFilter = filter;
    _contactSections = _buildContactSections(sessionUserProvider());
    notifyListeners();
  }

  Future<void> updateAppPreferences(AppPreferencesState state) async {
    _appPreferences = state;
    await _preferencesStore.writeAppPreferences(state);
    _conversationItems = await _buildConversationItems(sessionUserProvider());
    notifyListeners();
  }

  Future<String> exportBackup(String recoveryPassphrase) async {
    final blob = await cryptoCoreFacade.exportEncryptedBackup(
      BackupExportRequest(recoveryPassphrase: recoveryPassphrase),
    );
    final bytes = utf8.encode(blob);
    await apiClient.put('/users/me/crypto-backup', {
      'version': 1,
      'encrypted_blob': blob,
      'blob_sha256': sha256.convert(bytes).toString(),
    });
    _backupState = _backupState.copyWith(
      lastExportedBlob: blob,
      statusMessage: 'Encrypted backup tayyor bo‘ldi.',
      statusTone: UiStatusTone.success,
    );
    notifyListeners();
    return blob;
  }

  Future<String?> downloadServerBackup() async {
    final response = await apiClient.get('/users/me/crypto-backup');
    if (response is! Map || response['available'] != true) return null;
    final blob = response['encrypted_blob'] as String?;
    if (blob == null || blob.isEmpty) return null;
    return blob;
  }

  Future<void> syncEnterpriseRecoveryManifest() async {
    if (!ApiConfig.baseUrl.toLowerCase().startsWith('https://')) {
      _backupState = _backupState.copyWith(
        statusMessage: 'Automatic recovery is waiting for HTTPS transport.',
        statusTone: UiStatusTone.warning,
      );
      notifyListeners();
      return;
    }
    final response = await apiClient.get('/users/me/crypto-recovery');
    final sequence = response is Map && response['available'] == true
        ? response['sequence'] as int? ?? 0
        : 0;
    await _publishEnterpriseRecoverySnapshot(expectedSequence: sequence);
    _backupState = _backupState.copyWith(
      statusMessage:
          'Enterprise recovery snapshot is synchronized. Restore history explicitly from Security when needed.',
      statusTone: UiStatusTone.success,
    );
    notifyListeners();
  }

  /// Explicit user action: the app must never silently import escrowed keys
  /// while merely opening a chat list on a newly installed device.
  Future<void> restoreEnterpriseRecovery() async {
    Map<String, String>? queryParameters;
    final challenge = _recoveryApprovalChallenge;
    if (challenge != null && challenge.isNotEmpty) {
      queryParameters = {'approval': challenge};
    }
    dynamic response;
    try {
      response = await apiClient.get(
        '/users/me/crypto-recovery',
        queryParameters: queryParameters,
      );
    } on ApiException catch (error) {
      if (error.code != 'recovery_approval_required') rethrow;
      final approval = await apiClient.post(
        '/users/me/crypto-recovery/approvals',
        {'requester_device_id': sessionUserProvider().deviceId},
      ) as Map<String, dynamic>;
      _recoveryApprovalChallenge = approval['challenge'] as String?;
      _backupState = _backupState.copyWith(
        statusMessage:
            'Recovery request sent. Approve it from another active device, then press Restore again.',
        statusTone: UiStatusTone.warning,
      );
      notifyListeners();
      return;
    }
    if (response is! Map || response['available'] != true) {
      throw ApiException('No enterprise recovery manifest is available.');
    }
    final records = response['records'] as List<dynamic>? ?? const [];
    if (records.isEmpty) {
      throw ApiException('Enterprise recovery manifest has no records.');
    }
    for (final record in records) {
      final payload = (record as Map)['payload'] as String?;
      if (payload != null && payload.isNotEmpty) {
        await cryptoCoreFacade.importEnterpriseRecoveryManifest(payload);
      }
    }
    final historical = await cryptoCoreFacade.historicalDecryptCheck();
    _securityState = _securityState.copyWith(
      hasHistoricalDecryptCapability: historical.hasHistoricalCapability,
      availableHistoricalKeysets: historical.availableKeysets,
    );
    _backupState = _backupState.copyWith(
      statusMessage: 'Enterprise history recovery completed.',
      statusTone: UiStatusTone.success,
    );
    await refresh();
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> pendingRecoveryApprovals() async {
    final response = await apiClient.get('/users/me/crypto-recovery/approvals');
    if (response is! Map) return const [];
    return (response['approvals'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<void> decideRecoveryApproval({
    required int approvalId,
    required bool approved,
  }) {
    return apiClient.post(
      '/users/me/crypto-recovery/approvals/$approvalId',
      {
        'approver_device_id': sessionUserProvider().deviceId,
        'approved': approved,
      },
    );
  }

  Future<void> _publishEnterpriseRecoverySnapshot({
    required int expectedSequence,
  }) async {
    final payload = await cryptoCoreFacade.exportEnterpriseRecoveryManifest();
    final deviceId = sessionUserProvider().deviceId;
    try {
      await apiClient.put('/users/me/crypto-recovery', {
        'schema_version': 2,
        'payload': payload,
        'source_device_id': deviceId,
        'expected_sequence': expectedSequence,
      });
    } on ApiException catch (error) {
      if (error.code != 'recovery_manifest_conflict') rethrow;
      final latest = await apiClient.get('/users/me/crypto-recovery');
      if (latest is! Map || latest['available'] != true) rethrow;
      await apiClient.put('/users/me/crypto-recovery', {
        'schema_version': 2,
        'payload': payload,
        'source_device_id': deviceId,
        'expected_sequence': latest['sequence'] as int? ?? 0,
      });
    }
  }

  Future<void> importBackup({
    required String recoveryPassphrase,
    required String encryptedBlob,
  }) async {
    try {
      await cryptoCoreFacade.importEncryptedBackup(
        BackupImportRequest(
          recoveryPassphrase: recoveryPassphrase,
          encryptedBlob: encryptedBlob.trim(),
        ),
      );
      final historical = await cryptoCoreFacade.historicalDecryptCheck();
      _securityState = _securityState.copyWith(
        hasHistoricalDecryptCapability: historical.hasHistoricalCapability,
        availableHistoricalKeysets: historical.availableKeysets,
      );
      _backupState = _backupState.copyWith(
        statusMessage: 'Backup muvaffaqiyatli tiklandi.',
        statusTone: UiStatusTone.success,
      );
    } catch (error) {
      final message = error.toString().toLowerCase();
      final normalized = message.contains('passphrase')
          ? 'Recovery passphrase noto‘g‘ri.'
          : message.contains('corrupted')
          ? 'Backup blob buzilgan.'
          : message.contains('unsupported')
          ? 'Backup versiyasi qo‘llab-quvvatlanmaydi.'
          : error.toString();
      _backupState = _backupState.copyWith(
        statusMessage: normalized,
        statusTone: UiStatusTone.danger,
      );
    }
    notifyListeners();
  }

  Future<void> clearBackupFeedback() async {
    _backupState = const BackupRecoveryState();
    notifyListeners();
  }

  Future<void> _persistChatPreferences() {
    final sessionUser = sessionUserProvider();
    return _preferencesStore.writeChatListPreferences(
      accountId: sessionUser.accountId,
      workspaceId: sessionUser.activeWorkspaceId,
      preferencesState: _chatPreferences,
    );
  }

  Future<List<ConversationListItemState>> _buildConversationItems(
    SessionUser sessionUser,
  ) async {
    final rows = await _database.readConversations();
    final rowMap = {
      for (final row in rows)
        if (row.workspaceId == sessionUser.activeWorkspaceId ||
            row.workspaceId == 0)
          row.id: row,
    };
    final draftMap = <int, String>{};
    final localPreviewMap = <int, String>{};
    final messageStateMap = <int, MessageDeliveryState?>{};
    for (final conversation in _conversations) {
      final draft = await _database.readDraft(conversation.id);
      if (draft != null && draft.draftText.trim().isNotEmpty) {
        draftMap[conversation.id] = draft.draftText.trim();
      }
      final messages = await _database.readMessagesForConversation(
        conversation.id,
      );
      if (messages.isNotEmpty) {
        final latest = messages.last;
        final body = latest.plaintextBody.trim();
        if (body.isNotEmpty &&
            !body.startsWith('[decrypt-') &&
            !body.contains('Historical decrypt unavailable')) {
          localPreviewMap[conversation.id] = body;
        }
        if (latest.senderId == currentUserId) {
          messageStateMap[conversation.id] = _deliveryStateFromStored(
            latest.deliveryState,
          );
        }
      }
    }

    final items = _conversations
        .map((conversation) {
          final peerId = conversation.participantIds.firstWhere(
            (id) => id != currentUserId,
            orElse: () => -1,
          );
          final peerUser = _users
              .where((user) => user.id == peerId)
              .firstOrNull;
          final trust = peerUser == null ? null : _trustByUserId[peerUser.id];
          final draftPreview = draftMap[conversation.id];
          final row = rowMap[conversation.id];
          final unreadCount = row?.unreadCount ?? conversation.unreadCount;
          final archived = _chatPreferences.archivedConversationIds.contains(
            conversation.id,
          );
          final manuallyUnread = _chatPreferences.manuallyUnreadConversationIds
              .contains(conversation.id);
          return ConversationListItemState(
            conversation: conversation,
            title: conversation.isGroup
                ? conversation.title
                : (peerUser?.displayName.isNotEmpty == true
                      ? peerUser!.displayName
                      : conversation.title),
            preview: draftPreview != null && _appPreferences.keepDrafts
                ? 'Draft: $draftPreview'
                : localPreviewMap[conversation.id] ??
                      conversation.lastMessagePreview,
            draftPreview: draftPreview,
            unreadCount: unreadCount,
            isPinned: _chatPreferences.pinnedConversationIds.contains(
              conversation.id,
            ),
            isArchived: archived,
            isManuallyUnread: manuallyUnread,
            updatedAt: conversation.updatedAt,
            deliveryState: messageStateMap[conversation.id],
            trustBadge: conversation.isGroup
                ? const ContactTrustBadgeState(
                    label: 'Encrypted',
                    tone: UiStatusTone.info,
                  )
                : trust == null
                ? null
                : _badgeForTrust(trust),
            deviceSummary: conversation.isGroup
                ? 'Workspace encrypted'
                : _deviceSummaryForUser(peerUser),
          );
        })
        .where(_matchesConversationFilter)
        .toList();

    items.sort((a, b) {
      final pinnedA = a.isPinned ? 1 : 0;
      final pinnedB = b.isPinned ? 1 : 0;
      if (pinnedA != pinnedB) {
        return pinnedB.compareTo(pinnedA);
      }
      if (a.isUnread != b.isUnread) {
        return a.isUnread ? -1 : 1;
      }
      if (a.hasDraft != b.hasDraft) {
        return a.hasDraft ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return items;
  }

  bool _matchesConversationFilter(ConversationListItemState item) {
    final query = _chatPreferences.searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      final haystack = '${item.title} ${item.preview} ${item.deviceSummary}'
          .toLowerCase();
      if (!haystack.contains(query)) {
        return false;
      }
    }

    final selectedFilter = _chatPreferences.selectedFilter;
    if (selectedFilter == ChatListFilter.archived) {
      return item.isArchived;
    }
    if (selectedFilter != ChatListFilter.archived && item.isArchived) {
      return _appPreferences.showArchivedByDefault &&
          selectedFilter == ChatListFilter.all;
    }
    switch (selectedFilter) {
      case ChatListFilter.unread:
        return item.isUnread;
      case ChatListFilter.pinned:
        return item.isPinned;
      case ChatListFilter.archived:
        return item.isArchived;
      case ChatListFilter.all:
        return true;
    }
  }

  List<ContactsSectionState> _buildContactSections(SessionUser sessionUser) {
    final items = _users
        .map(
          (user) => ContactListItemState(
            user: user,
            title: user.id == sessionUser.id
                ? '${user.displayName} (You)'
                : user.displayName,
            subtitle: user.username,
            sortKey: user.displayName.toLowerCase(),
            badge: _buildContactBadge(user),
            deviceSummary: _deviceSummaryForUser(user),
            hasExistingConversation: _findPrivateConversation(user.id) != null,
            privateConversation: _findPrivateConversation(user.id),
            isCurrentUser: user.id == sessionUser.id,
          ),
        )
        .where(_matchesContactFilter)
        .toList();

    items.sort((a, b) {
      if (a.isCurrentUser != b.isCurrentUser) {
        return a.isCurrentUser ? -1 : 1;
      }
      final aPriority = _trustPriority(a.badge);
      final bPriority = _trustPriority(b.badge);
      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }
      return a.sortKey.compareTo(b.sortKey);
    });

    final you = items.where((item) => item.isCurrentUser).toList();
    final grouped = <String, List<ContactListItemState>>{};
    for (final item in items.where((item) => !item.isCurrentUser)) {
      final label = item.title.isEmpty
          ? '#'
          : item.title.substring(0, 1).toUpperCase();
      grouped.putIfAbsent(label, () => <ContactListItemState>[]).add(item);
    }
    final sections = <ContactsSectionState>[];
    if (you.isNotEmpty) {
      sections.add(ContactsSectionState(label: 'You', items: you));
    }
    final keys = grouped.keys.toList()..sort();
    for (final key in keys) {
      sections.add(ContactsSectionState(label: key, items: grouped[key]!));
    }
    return sections;
  }

  bool _matchesContactFilter(ContactListItemState item) {
    final query = _contactsSearchQuery.trim().toLowerCase();
    if (query.isNotEmpty &&
        !('${item.title} ${item.subtitle} ${item.deviceSummary}'
            .toLowerCase()
            .contains(query))) {
      return false;
    }
    switch (_contactsFilter) {
      case ContactsTrustFilter.verified:
        return item.badge.tone == UiStatusTone.success;
      case ContactsTrustFilter.needsAttention:
        return item.badge.tone == UiStatusTone.warning;
      case ContactsTrustFilter.notReady:
        return item.badge.tone == UiStatusTone.danger;
      case ContactsTrustFilter.all:
        return true;
    }
  }

  ContactTrustBadgeState _buildContactBadge(AppUser user) {
    if (user.id == currentUserId) {
      return const ContactTrustBadgeState(
        label: 'Current device set',
        tone: UiStatusTone.info,
      );
    }
    final trust = _trustByUserId[user.id];
    if (trust == null) {
      return const ContactTrustBadgeState(
        label: 'Unknown',
        tone: UiStatusTone.info,
      );
    }
    return _badgeForTrust(trust);
  }

  ContactTrustBadgeState _badgeForTrust(UserKeyTrust trust) {
    if (!trust.hasUsablePqcKey || !trust.hasUsableSigningKey) {
      return const ContactTrustBadgeState(
        label: 'Not ready',
        tone: UiStatusTone.danger,
        details: 'Peer usable PQC material yetarli emas.',
      );
    }
    if (trust.hasAnyKeyChanged) {
      return const ContactTrustBadgeState(
        label: 'Key changed',
        tone: UiStatusTone.warning,
        details: 'Security material changed, re-verify kerak.',
      );
    }
    if (trust.isEnterpriseVerified) {
      return const ContactTrustBadgeState(
        label: 'Verified',
        tone: UiStatusTone.success,
        details: 'Enterprise trust tasdiqlangan.',
      );
    }
    return const ContactTrustBadgeState(
      label: 'Ready',
      tone: UiStatusTone.info,
      details: 'PQC ready, lekin hali verify qilinmagan.',
    );
  }

  String _deviceSummaryForUser(AppUser? user) {
    if (user == null) {
      return 'Peer not available';
    }
    final activeCount = user.activeDevices.length;
    final readyCount = user.activeDevices
        .where((item) => item.hasUsableMlKemKey && item.hasUsableMlDsaKey)
        .length;
    if (readyCount == 0) {
      return '$activeCount active device • not ready';
    }
    if (readyCount == activeCount) {
      return '$readyCount/$activeCount devices ready';
    }
    return '$readyCount/$activeCount devices ready • attention needed';
  }

  SecurityCenterState _buildSecurityState({
    required List<AppUser> users,
    required Map<int, UserKeyTrust> trustByUserId,
    required SessionUser sessionUser,
    required HistoricalDecryptCheck historical,
  }) {
    var verified = 0;
    var attention = 0;
    var notReady = 0;
    for (final user in users) {
      if (user.id == sessionUser.id) {
        continue;
      }
      final trust = trustByUserId[user.id];
      if (trust == null) {
        continue;
      }
      if (!trust.hasUsablePqcKey || !trust.hasUsableSigningKey) {
        notReady += 1;
        continue;
      }
      if (trust.hasAnyKeyChanged) {
        attention += 1;
        continue;
      }
      if (trust.isEnterpriseVerified) {
        verified += 1;
      }
    }
    final currentUser = users
        .where((item) => item.id == sessionUser.id)
        .firstOrNull;
    final currentDevice = currentUser?.devices
        .where((item) => item.deviceId == sessionUser.deviceId)
        .firstOrNull;
    final isCurrentDeviceReady =
        currentDevice != null &&
        currentDevice.hasUsableMlKemKey &&
        currentDevice.hasUsableMlDsaKey &&
        currentDevice.isActive;
    return SecurityCenterState(
      verifiedPeersCount: verified,
      needsAttentionCount: attention,
      notReadyCount: notReady,
      isCurrentDeviceReady: isCurrentDeviceReady,
      hasHistoricalDecryptCapability: historical.hasHistoricalCapability,
      availableHistoricalKeysets: historical.availableKeysets,
    );
  }

  WorkspaceSummary? _findCurrentWorkspace(SessionUser sessionUser) {
    for (final organization in sessionUser.organizations) {
      for (final workspace in organization.workspaces) {
        if (workspace.id == sessionUser.activeWorkspaceId) {
          return workspace;
        }
      }
    }
    return null;
  }

  Conversation? _findPrivateConversation(int otherUserId) {
    for (final conversation in _conversations) {
      if (conversation.isGroup) {
        continue;
      }
      if (conversation.participantIds.contains(otherUserId)) {
        return conversation;
      }
    }
    return null;
  }

  MessageDeliveryState _deliveryStateFromStored(String value) {
    switch (value) {
      case 'pending':
        return MessageDeliveryState.pending;
      case 'failed-retryable':
        return MessageDeliveryState.failedRetryable;
      case 'failed-permanent':
        return MessageDeliveryState.failedPermanent;
      case 'sent':
      default:
        return MessageDeliveryState.sent;
    }
  }

  int _trustPriority(ContactTrustBadgeState badge) {
    switch (badge.tone) {
      case UiStatusTone.success:
        return 0;
      case UiStatusTone.info:
        return 1;
      case UiStatusTone.warning:
        return 2;
      case UiStatusTone.danger:
        return 3;
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

extension on SecurityCenterState {
  SecurityCenterState copyWith({
    bool? hasHistoricalDecryptCapability,
    int? availableHistoricalKeysets,
  }) {
    return SecurityCenterState(
      verifiedPeersCount: verifiedPeersCount,
      needsAttentionCount: needsAttentionCount,
      notReadyCount: notReadyCount,
      isCurrentDeviceReady: isCurrentDeviceReady,
      hasHistoricalDecryptCapability:
          hasHistoricalDecryptCapability ?? this.hasHistoricalDecryptCapability,
      availableHistoricalKeysets:
          availableHistoricalKeysets ?? this.availableHistoricalKeysets,
    );
  }
}
