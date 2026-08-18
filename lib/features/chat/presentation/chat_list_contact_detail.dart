part of 'chat_list_page.dart';

class _ContactDetailPage extends StatelessWidget {
  const _ContactDetailPage({
    required this.item,
    required this.detail,
    required this.onStartChat,
    required this.onVerify,
    required this.onRoleChanged,
  });

  final ContactListItemState item;
  final ContactDetailState detail;
  final Future<void> Function()? onStartChat;
  final Future<void> Function()? onVerify;
  final Future<void> Function(String role)? onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return AppScaffold(
      appBar: AppBar(title: const Text('Kontakt ma’lumotlari')),
      body: ListView(
        padding: EdgeInsets.all(spacing.lg),
        children: [
          AppSurfaceCard(
            child: Row(
              children: [
                AppAvatar(
                  label: item.user.displayName,
                  imageUrl: item.user.avatarUrl,
                  radius: 28,
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.user.displayName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        '${item.user.roleLabel} • ${item.user.username}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.lg),
          AppSurfaceCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.badge_outlined,
                color: context.appColors.primary,
              ),
              title: const Text('Korporativ roli'),
              subtitle: Text(item.user.roleLabel),
              trailing: onRoleChanged == null
                  ? null
                  : const Icon(Icons.chevron_right_rounded),
              onTap: onRoleChanged == null
                  ? null
                  : () => _showRolePicker(context),
            ),
          ),
          SizedBox(height: spacing.lg),
          AppBadge(
            label: detail.badge.label,
            tone: _mapTone(detail.badge.tone),
          ),
          SizedBox(height: spacing.md),
          AppStatusBanner(
            message: detail.badge.details ?? detail.deviceSummary,
            tone: _mapTone(detail.badge.tone),
          ),
          SizedBox(height: spacing.lg),
          const AppSectionHeader(
            title: 'Qurilmalar',
            subtitle: 'Kontaktning ko‘rinadigan qurilmalari.',
          ),
          SizedBox(height: spacing.sm),
          if (detail.devices.isEmpty)
            const AppEmptyState(
              message: 'Bu kontakt uchun ko‘rinadigan qurilma yo‘q.',
              icon: Icons.devices_outlined,
            )
          else
            for (final device in detail.devices)
              Padding(
                padding: EdgeInsets.only(bottom: spacing.sm),
                child: AppSurfaceCard(
                  child: Row(
                    children: [
                      const AppAvatar(
                        label: 'D',
                        icon: Icons.devices_outlined,
                        radius: 18,
                      ),
                      SizedBox(width: spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.deviceName.isEmpty
                                  ? device.deviceId
                                  : device.deviceName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            SizedBox(height: spacing.xs),
                            Text(
                              '${device.platform.isEmpty ? 'noma’lum' : device.platform} • ${device.isActive ? 'faol' : device.status} • ${device.hasUsableMlKemKey && device.hasUsableMlDsaKey ? 'tayyor' : 'tayyor emas'}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: context.appColors.textMuted,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          SizedBox(height: spacing.lg),
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton(
                  onPressed: item.isCurrentUser
                      ? null
                      : () async {
                          await onStartChat?.call();
                          if (context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                  label: Text(
                    detail.hasExistingConversation
                        ? 'Chatni ochish'
                        : 'Chat boshlash',
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: AppSecondaryButton(
                  onPressed: onVerify == null
                      ? null
                      : () async {
                          await onVerify!.call();
                          if (context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                  label: const Text('Kalitni tasdiqlash'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showRolePicker(BuildContext context) async {
    const roles = <(String, String, IconData)>[
      ('owner', 'Egasi', Icons.workspace_premium_outlined),
      ('admin', 'Administrator', Icons.admin_panel_settings_outlined),
      ('manager', 'Menejer', Icons.supervisor_account_outlined),
      ('member', 'Xodim', Icons.badge_outlined),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.appSpacing.md,
            0,
            context.appSpacing.md,
            context.appSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.all(context.appSpacing.sm),
                child: Text(
                  'Rolni tanlang',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final role in roles)
                ListTile(
                  leading: Icon(role.$3),
                  title: Text(role.$2),
                  trailing: item.user.role == role.$1
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: context.appColors.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(role.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != item.user.role) {
      await onRoleChanged!(selected);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  AppStatusTone _mapTone(UiStatusTone tone) {
    switch (tone) {
      case UiStatusTone.success:
        return AppStatusTone.success;
      case UiStatusTone.warning:
        return AppStatusTone.warning;
      case UiStatusTone.danger:
        return AppStatusTone.danger;
      case UiStatusTone.info:
        return AppStatusTone.info;
    }
  }
}
