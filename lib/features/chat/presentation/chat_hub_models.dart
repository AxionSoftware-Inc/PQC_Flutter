part of 'chat_hub_controller.dart';

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
    this.avatarUrl = '',
    this.roleLabel = '',
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
  final String avatarUrl;
  final String roleLabel;

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
