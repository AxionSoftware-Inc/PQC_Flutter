part of 'chat_list_page.dart';

class _ContactListRow extends StatelessWidget {
  const _ContactListRow({required this.item, required this.onTap});

  final ContactListItemState item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final toneColor = switch (item.badge.tone) {
      UiStatusTone.success => colors.success,
      UiStatusTone.warning => colors.warning,
      UiStatusTone.danger => colors.danger,
      UiStatusTone.info => colors.info,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.appRadii.md),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: spacing.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: 0.72)),
            ),
          ),
          child: Row(
            children: [
              AppAvatar(
                label: item.user.displayName,
                imageUrl: item.user.avatarUrl,
                radius: 24,
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      item.subtitle.isEmpty
                          ? item.deviceSummary
                          : item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                    ),
                    SizedBox(height: spacing.xs),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: toneColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: spacing.xs),
                        Flexible(
                          child: Text(
                            item.badge.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: toneColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              Icon(
                item.isCurrentUser
                    ? Icons.person_outline_rounded
                    : item.hasExistingConversation
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.chevron_right_rounded,
                size: item.hasExistingConversation ? 19 : 22,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

class _FilterOption<T> {
  const _FilterOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _FilterStrip<T> extends StatelessWidget {
  const _FilterStrip({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<_FilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < options.length; index++) ...[
            ChoiceChip(
              label: Text(options[index].label),
              selected: options[index].value == selected,
              onSelected: (_) => onSelected(options[index].value),
              showCheckmark: false,
              selectedColor: colors.primary,
              backgroundColor: colors.surfaceMuted,
              side: BorderSide(
                color: options[index].value == selected
                    ? colors.primary
                    : colors.border,
              ),
              labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: options[index].value == selected
                    ? Colors.white
                    : colors.textMuted,
                fontWeight: FontWeight.w700,
              ),
              padding: EdgeInsets.symmetric(horizontal: spacing.sm),
            ),
            if (index < options.length - 1) SizedBox(width: spacing.sm),
          ],
        ],
      ),
    );
  }
}

class _TabMeta {
  const _TabMeta({
    required this.label,
    required this.icon,
    required this.title,
  });

  final String label;
  final List<List<dynamic>> icon;
  final String title;
}
