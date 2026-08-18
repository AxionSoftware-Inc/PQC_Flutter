part of 'chat_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatPageTransferViews on _ChatPageState {
  Widget _buildTransferSection({
    required bool expanded,
    required VoidCallback onToggleExpanded,
  }) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final transfers = _visibleAttachmentTransfers;
    final activeCount = transfers
        .where((item) => item.status != AttachmentTransferStatus.failed)
        .length;
    return AppSurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(context.appRadii.md),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Row(
                children: [
                  Icon(
                    Icons.sync_alt_rounded,
                    size: 18,
                    color: colors.textMuted,
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.antiQText(uz: 'Uzatmalar', en: 'Transfers'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          activeCount > 0
                              ? context.antiQText(
                                  uz: '$activeCount faol • ${transfers.length} jami',
                                  en: '$activeCount active • ${transfers.length} total',
                                )
                              : context.antiQText(
                                  uz: '${transfers.length} muvaffaqiyatsiz uzatma',
                                  en: '${transfers.length} failed transfers',
                                ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            SizedBox(height: spacing.sm),
            ...transfers.map(
              (transfer) => Padding(
                padding: EdgeInsets.only(bottom: spacing.sm),
                child: _buildTransferTile(transfer),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransferTile(AttachmentTransferState transfer) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final progress = transfer.progress.fraction.clamp(0, 1).toDouble();
    final isTerminal =
        transfer.status == AttachmentTransferStatus.completed ||
        transfer.status == AttachmentTransferStatus.failed;
    return Container(
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.appRadii.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                transfer.direction == AttachmentTransferDirection.upload
                    ? Icons.upload_file_rounded
                    : Icons.download_rounded,
                size: 18,
                color: colors.textMuted,
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Text(
                  transfer.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                _transferPercentLabel(transfer),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Text(
            _transferStatusLabel(transfer),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
          SizedBox(height: spacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(context.appRadii.sm),
            child: LinearProgressIndicator(
              value: isTerminal ? 1 : progress,
              minHeight: 4,
            ),
          ),
          SizedBox(height: spacing.xs),
          Wrap(
            spacing: spacing.xs,
            runSpacing: spacing.xs,
            children: [
              if (!isTerminal &&
                  transfer.status != AttachmentTransferStatus.paused)
                AppSecondaryButton(
                  onPressed: () => _controller.pauseTransfer(transfer.localId),
                  label: Text(context.antiQText(uz: 'To‘xtatish', en: 'Pause')),
                ),
              if (transfer.status == AttachmentTransferStatus.paused)
                AppPrimaryButton(
                  onPressed: () => _resumeTransfer(transfer),
                  label: Text(
                    context.antiQText(uz: 'Davom ettirish', en: 'Resume'),
                  ),
                ),
              if (transfer.status == AttachmentTransferStatus.failed)
                AppPrimaryButton(
                  onPressed: () => _resumeTransfer(transfer),
                  label: Text(
                    context.antiQText(uz: 'Qayta urinish', en: 'Retry'),
                  ),
                ),
              if (transfer.status == AttachmentTransferStatus.completed)
                AppSecondaryButton(
                  onPressed: () =>
                      _controller.clearCompletedTransfer(transfer.localId),
                  label: Text(context.antiQText(uz: 'Tozalash', en: 'Clear')),
                ),
              AppSecondaryButton(
                onPressed: () => _controller.cancelTransfer(transfer.localId),
                label: Text(
                  context.antiQText(uz: 'Bekor qilish', en: 'Cancel'),
                ),
              ),
            ],
          ),
          if (transfer.error?.isNotEmpty == true) ...[
            SizedBox(height: spacing.xs),
            Text(
              transfer.error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _resumeTransfer(AttachmentTransferState transfer) async {
    try {
      await _controller.resumeTransfer(transfer.localId);
      if (transfer.direction == AttachmentTransferDirection.download &&
          transfer.attachmentId != null) {
        final attachments = _controller.messages.expand(
          (item) => item.attachments,
        );
        for (final attachment in attachments) {
          if (attachment.id == transfer.attachmentId) {
            await _controller.downloadAttachment(attachment);
            break;
          }
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _transferPercentLabel(AttachmentTransferState transfer) {
    final fraction = transfer.progress.fraction;
    if (transfer.progress.totalChunks <= 0) {
      return '';
    }
    return '${(fraction * 100).round()}%';
  }

  String _transferStatusLabel(AttachmentTransferState transfer) {
    switch (transfer.status) {
      case AttachmentTransferStatus.queued:
        return transfer.direction == AttachmentTransferDirection.upload
            ? context.antiQText(
                uz: 'Yuborish navbatida',
                en: 'Queued for upload',
              )
            : context.antiQText(
                uz: 'Yuklab olish navbatida',
                en: 'Queued for download',
              );
      case AttachmentTransferStatus.encrypting:
        return context.antiQText(uz: 'Shifrlanmoqda', en: 'Encrypting');
      case AttachmentTransferStatus.uploading:
        return context.antiQText(uz: 'Yuborilmoqda', en: 'Uploading');
      case AttachmentTransferStatus.downloading:
        return context.antiQText(uz: 'Yuklab olinmoqda', en: 'Downloading');
      case AttachmentTransferStatus.paused:
        return context.antiQText(uz: 'To‘xtatilgan', en: 'Paused');
      case AttachmentTransferStatus.retrying:
        return context.antiQText(uz: 'Qayta urinilmoqda', en: 'Retrying');
      case AttachmentTransferStatus.verifying:
        return context.antiQText(uz: 'Tekshirilmoqda', en: 'Verifying');
      case AttachmentTransferStatus.completed:
        return transfer.direction == AttachmentTransferDirection.upload
            ? context.antiQText(uz: 'Yuborildi', en: 'Uploaded')
            : context.antiQText(uz: 'Yuklab olindi', en: 'Downloaded');
      case AttachmentTransferStatus.failed:
        return context.antiQText(uz: 'Xatolik', en: 'Failed');
    }
  }

  String _formatBytes(int bytes) {
    return TransferPolicy.formatBytes(bytes);
  }

  String _formatMessageTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _inferMimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.m4v')) return 'video/x-m4v';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    if (lower.endsWith('.3gp')) return 'video/3gpp';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }
}
