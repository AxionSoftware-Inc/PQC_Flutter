import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/conversation.dart';
import '../../security/key_verification_service.dart';

class ChatConversationHeader extends StatelessWidget {
  const ChatConversationHeader({
    super.key,
    required this.title,
    required this.conversation,
    required this.trust,
    required this.brandLabel,
    required this.onBack,
    required this.onVerify,
    required this.transferCount,
    required this.isPeerOnline,
    required this.isPeerTyping,
    required this.peerLastSeenAt,
    this.onOpenContactDetails,
  });

  final String title;
  final Conversation conversation;
  final ConversationKeyTrust? trust;
  final String? brandLabel;
  final VoidCallback onBack;
  final Future<void> Function()? onVerify;
  final int transferCount;
  final bool isPeerOnline;
  final bool isPeerTyping;
  final DateTime? peerLastSeenAt;
  final Future<void> Function()? onOpenContactDetails;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return Container(
      padding: EdgeInsets.fromLTRB(
        spacing.xs,
        spacing.xs,
        spacing.md,
        spacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.appColors.background,
        border: Border(bottom: BorderSide(color: context.appColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip: 'Back',
          ),
          GestureDetector(
            onTap: onOpenContactDetails,
            child: AppAvatar(
              label: title,
              icon: conversation.isGroup ? Icons.forum_outlined : null,
              radius: 20,
            ),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: GestureDetector(
              onTap: onOpenContactDetails,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _headerSubtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appColors.textMuted,
                    ),
                  ),
                  if (!conversation.isGroup && (isPeerOnline || isPeerTyping))
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: isPeerTyping
                                ? context.appColors.primary
                                : Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isPeerTyping ? 'typing now' : 'active now',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: isPeerTyping
                                    ? context.appColors.primary
                                    : Colors.green.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (transferCount > 0)
            Icon(
              Icons.sync_rounded,
              size: 18,
              color: context.appColors.textMuted,
            ),
          if (onVerify != null)
            IconButton(
              onPressed: onVerify,
              icon: Icon(
                trust?.isEnterpriseVerified == true
                    ? Icons.verified_user_rounded
                    : Icons.shield_outlined,
              ),
            ),
        ],
      ),
    );
  }

  String _headerSubtitle() {
    if (!conversation.isGroup) {
      if (isPeerTyping) return 'typing…';
      if (isPeerOnline) return 'online';
      if (peerLastSeenAt != null) {
        final seen = peerLastSeenAt!.toLocal();
        return 'last seen ${seen.hour.toString().padLeft(2, '0')}:${seen.minute.toString().padLeft(2, '0')}';
      }
    }
    final base = conversation.isGroup
        ? 'Workspace group'
        : 'Private conversation';
    return brandLabel?.isNotEmpty == true ? '$base • $brandLabel' : base;
  }
}

class ChatSecurityBanner extends StatelessWidget {
  const ChatSecurityBanner({
    super.key,
    required this.trust,
    required this.onVerify,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  final ConversationKeyTrust trust;
  final Future<void> Function() onVerify;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final summary = !trust.isAvailable
        ? 'Peer device key hali tayyor emas.'
        : trust.hasEnterpriseKeyChanged
        ? 'Security material changed. Re-verify recommended.'
        : trust.isEnterpriseVerified
        ? 'Enterprise trust verified.'
        : trust.isEnterpriseReady
        ? 'PQC ready. First secure send can proceed.'
        : trust.isVerified
        ? 'Classical trust verified.'
        : 'Key not verified yet.';
    final tone = !trust.isAvailable || trust.hasEnterpriseKeyChanged
        ? AppStatusTone.warning
        : trust.isEnterpriseVerified || trust.isVerified
        ? AppStatusTone.success
        : trust.isEnterpriseReady
        ? AppStatusTone.info
        : AppStatusTone.info;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.appSpacing.sm,
        context.appSpacing.xs,
        context.appSpacing.sm,
        0,
      ),
      child: AppStatusBanner(
        message: summary,
        tone: tone,
        action: trust.isAvailable
            ? Wrap(
                spacing: context.appSpacing.xs,
                children: [
                  TextButton(
                    onPressed: onVerify,
                    child: Text(
                      trust.isEnterpriseVerified || trust.isVerified
                          ? 'Re-verify'
                          : 'Verify',
                    ),
                  ),
                  TextButton(
                    onPressed: onToggleExpanded,
                    child: Text(isExpanded ? 'Hide details' : 'Details'),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class ChatSecurityDetailCard extends StatelessWidget {
  const ChatSecurityDetailCard({super.key, required this.trust});

  final ConversationKeyTrust trust;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final rows = <(String, String)>[
      ('X25519', trust.fingerprint ?? '-'),
      ('PQC-KEM', trust.pqcFingerprint ?? '-'),
      ('ML-DSA', trust.signingFingerprint ?? '-'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.sm, spacing.xs, spacing.sm, 0),
      child: AppSurfaceCard(
        padding: EdgeInsets.all(spacing.md),
        backgroundColor: context.appColors.surfaceMuted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Security details',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: spacing.sm),
            ...rows.map(
              (row) => Padding(
                padding: EdgeInsets.only(bottom: spacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        row.$1,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
