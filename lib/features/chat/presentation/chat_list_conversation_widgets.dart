part of 'chat_list_page.dart';

class _ConversationListRow extends StatelessWidget {
  const _ConversationListRow({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onAvatarLongPress,
    required this.relativeTime,
  });

  final ConversationListItemState item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAvatarLongPress;
  final String relativeTime;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final isAttention =
        item.trustBadge?.tone == UiStatusTone.warning ||
        item.trustBadge?.tone == UiStatusTone.danger;
    final preview = item.hasDraft
        ? '${context.antiQText(uz: 'Qoralama', en: 'Draft')}: ${item.draftPreview!.trim()}'
        : item.preview.isEmpty
        ? context.antiQText(uz: 'Suhbatni ochish', en: 'Open conversation')
        : item.preview;

    return AnimatedContainer(
      duration: context.appDurations.fast,
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.only(bottom: context.appSpacing.xs),
      decoration: BoxDecoration(
        color: selected ? colors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(context.appRadii.md),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(context.appRadii.md),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              spacing.xs,
              spacing.sm,
              spacing.xs,
              spacing.sm,
            ),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: onAvatarLongPress,
                  child: AnimatedSwitcher(
                    duration: context.appDurations.fast,
                    child: selected
                        ? Container(
                            key: const ValueKey('selected'),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                            ),
                          )
                        : AppAvatar(
                            key: const ValueKey('avatar'),
                            label: item.title,
                            imageUrl: item.avatarUrl,
                            icon: item.conversation.isGroup
                                ? Icons.forum_outlined
                                : null,
                            radius: 22,
                          ),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: item.isUnread
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                  ),
                                ),
                                if (item.isPinned) ...[
                                  SizedBox(width: spacing.xs),
                                  Icon(
                                    Icons.push_pin_rounded,
                                    size: 14,
                                    color: colors.textMuted,
                                  ),
                                ],
                                if (isAttention) ...[
                                  SizedBox(width: spacing.xs),
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 15,
                                    color: colors.warning,
                                  ),
                                ],
                                if (item.roleLabel.isNotEmpty &&
                                    !item.conversation.isGroup) ...[
                                  SizedBox(width: spacing.xs),
                                  Flexible(
                                    child: Text(
                                      '• ${item.roleLabel}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colors.textMuted,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(width: spacing.sm),
                          Text(
                            relativeTime,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: item.isUnread
                                      ? colors.primary
                                      : colors.textMuted,
                                  fontWeight: item.isUnread
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (item.deliveryState != null) ...[
                            Icon(
                              _deliveryIcon(item.deliveryState!),
                              size: 15,
                              color: _deliveryColor(
                                colors,
                                item.deliveryState!,
                              ),
                            ),
                            SizedBox(width: spacing.xs),
                          ],
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: item.hasDraft
                                        ? colors.primary
                                        : colors.textMuted,
                                    fontWeight: item.hasDraft
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                            ),
                          ),
                          if (item.isUnread) ...[
                            SizedBox(width: spacing.sm),
                            Container(
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                item.unreadCount > 0
                                    ? '${item.unreadCount}'
                                    : '',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _deliveryIcon(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.pending:
        return Icons.schedule_rounded;
      case MessageDeliveryState.failedRetryable:
        return Icons.error_outline_rounded;
      case MessageDeliveryState.failedPermanent:
        return Icons.block_rounded;
      case MessageDeliveryState.sent:
        return Icons.done_all_rounded;
    }
  }

  Color _deliveryColor(AppColors colors, MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.pending:
        return colors.textMuted;
      case MessageDeliveryState.failedRetryable:
      case MessageDeliveryState.failedPermanent:
        return colors.danger;
      case MessageDeliveryState.sent:
        return colors.primary;
    }
  }
}
