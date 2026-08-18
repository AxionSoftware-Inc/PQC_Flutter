part of 'chat_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatPageAttachmentViews on _ChatPageState {
  Widget _buildAttachmentChip(
    ChatAttachment attachment, {
    ChatMessage? message,
    bool isMine = false,
    bool showDeliveryOverlay = false,
  }) {
    final transfer = _controller.findDownloadTransfer(attachment.id);
    final isBusy =
        transfer != null &&
        transfer.status != AttachmentTransferStatus.completed &&
        transfer.status != AttachmentTransferStatus.failed;
    final isImage = attachment.mimeType.startsWith('image/');
    final localPath = _downloadedAttachmentPaths[attachment.id];
    final label = transfer == null
        ? '${attachment.filename} (${_formatBytes(attachment.sizeBytes)})'
        : '${attachment.filename} • ${_transferStatusLabel(transfer)}';
    final onPressed = isBusy
        ? () async {
            await _controller.pauseTransfer(transfer.localId);
          }
        : () async {
            try {
              final path = await _controller.downloadAttachment(attachment);
              if (!mounted) {
                return;
              }
              if (isImage) {
                _downloadedAttachmentPaths[attachment.id] = path;
                if (mounted) setState(() {});
                await _showImageLightbox(attachment.filename, path);
                return;
              }
              if (kIsWeb) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fayl $path manziliga yuklandi')),
                );
                return;
              }
              final result = await OpenFilex.open(path);
              if (!mounted) {
                return;
              }
              if (result.type != ResultType.done) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result.message.isEmpty
                          ? 'Fayl yuklandi, lekin uni ochadigan dastur topilmadi.'
                          : result.message,
                    ),
                  ),
                );
              }
            } catch (error) {
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(error.toString())));
            }
          };
    if (isImage) {
      if (localPath != null && localPath.isNotEmpty) {
        return Stack(
          children: [
            InkWell(
              onTap: () => _showImageLightbox(attachment.filename, localPath),
              borderRadius: BorderRadius.circular(context.appRadii.sm),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(context.appRadii.sm),
                child: SizedBox(
                  width: 248,
                  child: buildChatLocalImage(context, localPath),
                ),
              ),
            ),
            if (showDeliveryOverlay && message != null)
              _buildImageDeliveryOverlay(message: message, isMine: isMine),
          ],
        );
      }
      return Stack(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(context.appRadii.sm),
              child: Ink(
                width: 248,
                height: 172,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(context.appRadii.sm),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.photo_outlined, size: 34),
                    SizedBox(height: context.appSpacing.xs),
                    Text(
                      context.antiQText(uz: 'Rasmni ochish', en: 'Open image'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showDeliveryOverlay && message != null)
            _buildImageDeliveryOverlay(message: message, isMine: isMine),
        ],
      );
    }
    return ActionChip(
      avatar: const Icon(Icons.insert_drive_file_outlined, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }

  Widget _buildMessageFooter({
    required ChatMessage message,
    required bool isMine,
  }) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (message.deliveryState != MessageDeliveryState.sent)
          Padding(
            padding: EdgeInsets.only(right: spacing.xs),
            child: Text(
              _statusLabel(message),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.72)
                    : colors.textMuted,
              ),
            ),
          ),
        Text(
          _formatMessageTime(message.createdAt),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isMine
                ? Colors.white.withValues(alpha: 0.68)
                : colors.textMuted,
          ),
        ),
        if (isMine)
          Padding(
            padding: EdgeInsets.only(left: spacing.xs),
            child: AnimatedSwitcher(
              duration: context.appDurations.fast,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                _deliveryIcon(message),
                key: ValueKey(
                  '${message.deliveryState.name}-${message.isRead}',
                ),
                size: 14,
                color: message.isRead
                    ? const Color(0xFFB9E6FF)
                    : Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageDeliveryOverlay({
    required ChatMessage message,
    required bool isMine,
  }) {
    return Positioned(
      right: 6,
      bottom: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(context.appRadii.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatMessageTime(message.createdAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 3),
                AnimatedSwitcher(
                  duration: context.appDurations.fast,
                  child: Icon(
                    _deliveryIcon(message),
                    key: ValueKey(
                      'image-${message.deliveryState.name}-${message.isRead}',
                    ),
                    size: 13,
                    color: message.isRead
                        ? const Color(0xFFB9E6FF)
                        : Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _deliveryIcon(ChatMessage message) {
    switch (message.deliveryState) {
      case MessageDeliveryState.pending:
        return Icons.schedule_rounded;
      case MessageDeliveryState.failedRetryable:
      case MessageDeliveryState.failedPermanent:
        return Icons.error_outline_rounded;
      case MessageDeliveryState.sent:
        return message.isRead ? Icons.done_all_rounded : Icons.done_rounded;
    }
  }

  Future<void> _showImageLightbox(String title, String path) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(child: buildChatLocalImageViewer(dialogContext, path)),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  tooltip: context.antiQText(
                    uz: 'Rasmni yopish',
                    en: 'Close image',
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
