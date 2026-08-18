part of 'chat_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatPageMessageItems on _ChatPageState {
  // Kept as a reference for the shared thread widget during the migration.
  // ignore: unused_element
  Widget _buildMessageItem({
    required ChatMessage message,
    required bool isMine,
    required AppColors colors,
    required AppSpacing spacing,
  }) {
    final isDecryptNeedsRestore =
        message.body == ChatCryptoService.decryptNeedsBackupRestoreMarker ||
        message.body == ChatCryptoService.decryptKeyMissingMarker;
    final isDecryptError = message.body == ChatCryptoService.decryptErrorMarker;
    final isImageOnly =
        message.attachments.length == 1 &&
        message.attachments.single.mimeType.startsWith('image/') &&
        message.body.trim().isEmpty &&
        !isDecryptNeedsRestore &&
        !isDecryptError;
    final hasInlineFooter =
        !isImageOnly &&
        !isDecryptNeedsRestore &&
        !isDecryptError &&
        message.body.trim().isNotEmpty;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: spacing.xs,
          vertical: spacing.xs,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: isImageOnly
                      ? EdgeInsets.zero
                      : EdgeInsets.symmetric(
                          horizontal: spacing.sm + 2,
                          vertical: spacing.xs + 3,
                        ),
                  decoration: BoxDecoration(
                    color: isImageOnly
                        ? Colors.transparent
                        : isMine
                        ? colors.chatMine
                        : colors.chatPeer,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(context.appRadii.md),
                      topRight: Radius.circular(context.appRadii.md),
                      bottomLeft: Radius.circular(
                        isMine ? context.appRadii.md : context.appRadii.sm,
                      ),
                      bottomRight: Radius.circular(
                        isMine ? context.appRadii.sm : context.appRadii.md,
                      ),
                    ),
                    border: isImageOnly || isMine
                        ? null
                        : Border.all(
                            color: colors.border.withValues(alpha: 0.62),
                          ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.conversation.isGroup &&
                          !isMine &&
                          !isImageOnly) ...[
                        Text(
                          message.senderName,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: colors.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        SizedBox(height: spacing.xs),
                      ],
                      if (message.attachments.isNotEmpty) ...[
                        Wrap(
                          spacing: spacing.xs,
                          runSpacing: spacing.xs,
                          children: message.attachments
                              .map(
                                (attachment) => _buildAttachmentChip(
                                  attachment,
                                  message: message,
                                  isMine: isMine,
                                  showDeliveryOverlay: isImageOnly,
                                ),
                              )
                              .toList(),
                        ),
                        if (message.body.trim().isNotEmpty)
                          SizedBox(height: spacing.sm),
                      ],
                      if (isDecryptNeedsRestore)
                        Text(
                          'Bu qurilmada eski xabar kaliti topilmadi. Xabarni o‘qish uchun tarixni tiklang.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: isMine ? Colors.white : null,
                                height: 1.35,
                              ),
                        )
                      else if (isDecryptError)
                        Text(
                          'Bu xabarni shifrdan chiqarib bo‘lmadi.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: isMine ? Colors.white : null,
                                height: 1.35,
                              ),
                        )
                      else if (message.body.trim().isNotEmpty)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: message.body),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.baseline,
                                baseline: TextBaseline.alphabetic,
                                child: Padding(
                                  padding: EdgeInsets.only(left: spacing.sm),
                                  child: _buildMessageFooter(
                                    message: message,
                                    isMine: isMine,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: isMine ? Colors.white : null,
                                height: 1.28,
                              ),
                        ),
                      if (!isImageOnly && !hasInlineFooter) ...[
                        SizedBox(height: spacing.xs),
                        _buildMessageFooter(message: message, isMine: isMine),
                      ],
                    ],
                  ),
                ),
                if (message.canRetry)
                  TextButton(
                    onPressed: () => _retryMessage(message),
                    child: Text(
                      context.antiQText(uz: 'Qayta urinish', en: 'Retry'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
