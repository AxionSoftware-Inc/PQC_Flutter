part of 'chat_hub_controller.dart';

// Projection members implement the contract declared by the base controller.
// ignore_for_file: annotate_overrides

mixin _ChatHubContactProjection on _ChatHubControllerBase {
  List<ContactsSectionState> _buildContactSections(SessionUser sessionUser) {
    final items = _users
        .map(
          (user) => ContactListItemState(
            user: user,
            title: user.id == sessionUser.id
                ? '${user.displayName} (Siz)'
                : user.displayName,
            subtitle: user.roleLabel,
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
}
