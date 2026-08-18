part of 'chat_page.dart';

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.title,
    required this.avatarUrl,
    required this.roleLabel,
    required this.conversation,
    required this.trust,
    required this.brandLabel,
    required this.onBack,
    required this.onOpenDetails,
    required this.onVerify,
    required this.transferCount,
  });

  final String title;
  final String avatarUrl;
  final String roleLabel;
  final Conversation conversation;
  final ConversationKeyTrust? trust;
  final String? brandLabel;
  final VoidCallback onBack;
  final VoidCallback onOpenDetails;
  final Future<void> Function()? onVerify;
  final int transferCount;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return Container(
      padding: EdgeInsets.fromLTRB(
        spacing.xs,
        spacing.sm,
        spacing.md,
        spacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.appColors.surface.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(
            color: context.appColors.border.withValues(alpha: 0.68),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            tooltip: 'Orqaga',
          ),
          InkWell(
            onTap: onOpenDetails,
            borderRadius: BorderRadius.circular(context.appRadii.pill),
            child: AppAvatar(
              label: title,
              imageUrl: avatarUrl,
              icon: conversation.isGroup ? Icons.forum_outlined : null,
              radius: 20,
            ),
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: InkWell(
              onTap: onOpenDetails,
              borderRadius: BorderRadius.circular(context.appRadii.sm),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: spacing.xs),
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
                  ],
                ),
              ),
            ),
          ),
          if (transferCount > 0)
            Container(
              padding: EdgeInsets.all(spacing.xs + 2),
              decoration: BoxDecoration(
                color: context.appColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.sync_rounded,
                size: 16,
                color: context.appColors.primary,
              ),
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
    final base = conversation.isGroup ? 'Guruh suhbati' : 'Shaxsiy suhbat';
    if (!conversation.isGroup && roleLabel.isNotEmpty) {
      return roleLabel;
    }
    if (brandLabel?.isNotEmpty == true) {
      return '$base • $brandLabel';
    }
    return base;
  }
}

class _ConversationProfilePage extends StatelessWidget {
  const _ConversationProfilePage({
    required this.title,
    required this.avatarUrl,
    required this.roleLabel,
    required this.conversation,
    required this.trust,
  });

  final String title;
  final String avatarUrl;
  final String roleLabel;
  final Conversation conversation;
  final ConversationKeyTrust? trust;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final isGroup = conversation.isGroup;
    final securityLabel = trust == null
        ? (isGroup ? 'Himoyalangan guruh suhbati' : 'Xavfsizlik mavjud emas')
        : trust!.isEnterpriseVerified
        ? 'Xavfsizlik tasdiqlangan'
        : trust!.isEnterpriseReady
        ? 'Xavfsiz kanal tayyor'
        : trust!.isVerified
        ? 'Qurilma kaliti tasdiqlangan'
        : 'Kalit tasdiqlanishi kutilmoqda';
    return AppScaffold(
      appBar: AppBar(
        title: Text(isGroup ? 'Guruh ma’lumotlari' : 'Kontakt ma’lumotlari'),
      ),
      body: ListView(
        padding: EdgeInsets.all(spacing.lg),
        children: [
          AppSurfaceCard(
            backgroundColor: colors.primarySoft,
            child: Column(
              children: [
                AppAvatar(
                  label: title,
                  imageUrl: avatarUrl,
                  icon: isGroup ? Icons.forum_outlined : null,
                  radius: 46,
                ),
                SizedBox(height: spacing.md),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                SizedBox(height: spacing.xs),
                Text(
                  isGroup
                      ? 'Guruh suhbati'
                      : (roleLabel.isEmpty ? 'Shaxsiy suhbat' : roleLabel),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.lg),
          AppSectionHeader(
            title: 'Suhbat',
            subtitle: isGroup
                ? 'Guruh xabarlari xavfsiz himoyalangan.'
                : 'Xabarlar boshidan oxirigacha shifrlangan.',
          ),
          SizedBox(height: spacing.sm),
          AppSurfaceCard(
            child: Column(
              children: [
                _ProfileInfoRow(
                  icon: Icons.lock_outline_rounded,
                  title: 'Xavfsizlik',
                  value: securityLabel,
                ),
                Divider(color: colors.border, height: spacing.lg),
                _ProfileInfoRow(
                  icon: Icons.photo_library_outlined,
                  title: 'Media',
                  value: 'Rasm va fayllar shu chatda saqlanadi',
                ),
                Divider(color: colors.border, height: spacing.lg),
                _ProfileInfoRow(
                  icon: isGroup
                      ? Icons.groups_2_outlined
                      : Icons.person_outline_rounded,
                  title: isGroup ? 'Turi' : 'Maxfiylik',
                  value: isGroup ? 'Guruh suhbati' : 'Shaxsiy suhbat',
                ),
              ],
            ),
          ),
          if (trust != null && !isGroup) ...[
            SizedBox(height: spacing.lg),
            const AppSectionHeader(
              title: 'Kalit holati',
              subtitle:
                  'Bu qurilma joriy himoyalangan kalitlar to‘plamidan foydalanadi.',
            ),
            SizedBox(height: spacing.sm),
            AppStatusBanner(
              message: securityLabel,
              tone: trust!.isEnterpriseVerified || trust!.isVerified
                  ? AppStatusTone.success
                  : AppStatusTone.info,
            ),
          ],
          SizedBox(height: spacing.lg),
          AppPrimaryButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Suhbatni ochish'),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.appColors.primary),
        SizedBox(width: context.appSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: context.appSpacing.xs),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
