part of 'chat_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatPageMessageStateViews on _ChatPageState {
  Widget _buildSelectedAttachmentTray() {
    final spacing = context.appSpacing;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedAttachments.length,
        separatorBuilder: (_, _) => SizedBox(width: spacing.xs),
        itemBuilder: (context, index) {
          final item = _selectedAttachments[index];
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.sm,
              vertical: spacing.xs,
            ),
            decoration: BoxDecoration(
              color: context.appColors.surfaceMuted,
              borderRadius: BorderRadius.circular(context.appRadii.pill),
              border: Border.all(color: context.appColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.isImage ? Icons.image_outlined : Icons.attach_file,
                  size: 16,
                  color: context.appColors.textMuted,
                ),
                SizedBox(width: spacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    '${item.name} (${_formatBytes(item.sizeBytes)})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SizedBox(width: spacing.xs),
                InkWell(
                  onTap: () => _removeSelectedAttachment(item),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    final spacing = context.appSpacing;
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) {
        final isMine = index.isEven;
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            margin: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.xs,
            ),
            child: AppSurfaceCard(
              backgroundColor: isMine
                  ? context.appColors.chatMine.withValues(alpha: 0.25)
                  : context.appColors.surface,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeletonBlock(height: 12, width: 80),
                  SizedBox(height: 10),
                  AppSkeletonBlock(height: 14),
                  SizedBox(height: 10),
                  AppSkeletonBlock(height: 14, width: 180),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ChatThreadMessage _toThreadMessage(ChatMessage message) {
    return ChatThreadMessage(
      id: message.id,
      senderId: message.senderId,
      senderName: message.senderName,
      body: message.body,
      createdAt: message.createdAt,
      isMine: message.senderId == widget.currentUserId,
      isRead: message.isRead,
      canRetry: message.canRetry,
      deliveryLabel: message.deliveryState.name,
      attachments: message.attachments
          .map(
            (attachment) => ChatThreadAttachment(
              id: attachment.id,
              filename: attachment.filename,
              mimeType: attachment.mimeType,
              sizeBytes: attachment.sizeBytes,
              raw: attachment,
            ),
          )
          .toList(),
      raw: message,
    );
  }
}
