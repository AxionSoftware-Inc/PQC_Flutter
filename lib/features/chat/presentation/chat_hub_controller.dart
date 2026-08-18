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
import 'package:chat_core/chat_core.dart' show ApiException;
import '../../account/data/account_repository.dart';
import '../../chat/application/chat_facade.dart';
import '../../crypto/durability/crypto_core_facade.dart';
import '../../crypto/durability/crypto_durability_models.dart';
import '../../security/key_verification_service.dart';

// Contract members are implemented by the controller mixins in this library.
// ignore_for_file: unused_element

part 'chat_hub_models.dart';
part 'chat_hub_actions.dart';
part 'chat_hub_backup_actions.dart';
part 'chat_hub_projection.dart';
part 'chat_hub_contact_projection.dart';
part 'chat_hub_conversation_projection.dart';

abstract class _ChatHubControllerBase extends ChangeNotifier {
  _ChatHubControllerBase({
    required this.chatFacade,
    required this.cryptoCoreFacade,
    required this.currentUserId,
    required this.sessionUserProvider,
    required this.accountRepository,
    required this.database,
    LocalUiPreferencesStore? preferencesStore,
  }) : _preferencesStore = preferencesStore ?? LocalUiPreferencesStore();

  final ChatFacade chatFacade;
  final CryptoCoreFacade cryptoCoreFacade;
  final int currentUserId;
  final SessionUser Function() sessionUserProvider;
  final AccountRepository accountRepository;
  final AppDatabase database;
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
  Map<String, dynamic> _accountSettings = const {};
  List<ConversationListItemState> _conversationItems = const [];
  List<ContactsSectionState> _contactSections = const [];
  String? _recoveryApprovalChallenge;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<AppUser> get users => List<AppUser>.unmodifiable(_users);
  ChatListViewState get chatState => ChatListViewState(
    preferences: _chatPreferences,
    items: _conversationItems,
  );
  ContactsViewState get contactsState => ContactsViewState(
    searchQuery: _contactsSearchQuery,
    selectedFilter: _contactsFilter,
    sections: _contactSections,
  );
  Map<String, dynamic> get accountSettings =>
      Map.unmodifiable(Map<String, dynamic>.of(_accountSettings));

  Map<int, UserKeyTrust> get trustByUserId => _trustByUserId;

  Future<List<ConversationListItemState>> _buildConversationItems(
    SessionUser sessionUser,
  );
  bool _matchesConversationFilter(ConversationListItemState item);
  List<ContactsSectionState> _buildContactSections(SessionUser sessionUser);
  bool _matchesContactFilter(ContactListItemState item);
  ContactTrustBadgeState _buildContactBadge(AppUser user);
  ContactTrustBadgeState _badgeForTrust(UserKeyTrust trust);
  String _deviceSummaryForUser(AppUser? user);
  SecurityCenterState _buildSecurityState({
    required List<AppUser> users,
    required Map<int, UserKeyTrust> trustByUserId,
    required SessionUser sessionUser,
    required HistoricalDecryptCheck historical,
  });
  WorkspaceSummary? _findCurrentWorkspace(SessionUser sessionUser);
  Conversation? _findPrivateConversation(int otherUserId);
  MessageDeliveryState _deliveryStateFromStored(String value);
  int _trustPriority(ContactTrustBadgeState badge);
}

class ChatHubController extends _ChatHubControllerBase
    with
        _ChatHubActions,
        _ChatHubBackupActions,
        _ChatHubProjection,
        _ChatHubContactProjection,
        _ChatHubConversationProjection {
  ChatHubController({
    required super.chatFacade,
    required super.cryptoCoreFacade,
    required super.currentUserId,
    required super.sessionUserProvider,
    required super.accountRepository,
    required super.database,
    super.preferencesStore,
  });
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
