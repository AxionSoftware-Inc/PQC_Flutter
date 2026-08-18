import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/attachment.dart';
import '../../transfers/application/attachment_transfer.dart';
import 'chat_local_image.dart';
import 'chat_transfer_indicator.dart';

class ChatAttachmentCard extends StatelessWidget {
  const ChatAttachmentCard({
    super.key,
    required this.attachment,
    required this.transfer,
    required this.localPath,
    required this.onPressed,
    required this.formatBytes,
    required this.statusLabel,
  });

  final ChatAttachment attachment;
  final AttachmentTransferState? transfer;
  final String? localPath;
  final VoidCallback? onPressed;
  final String Function(int bytes) formatBytes;
  final String Function(AttachmentTransferState transfer) statusLabel;

  bool get isImage => attachment.mimeType.startsWith('image/');

  bool get isBusy =>
      transfer != null &&
      transfer!.status != AttachmentTransferStatus.completed &&
      transfer!.status != AttachmentTransferStatus.failed;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final progress = transfer?.progress.fraction.clamp(0, 1).toDouble();
    final actionLabel = transfer == null
        ? 'Tap to download'
        : statusLabel(transfer!);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(context.appRadii.md),
        child: Container(
          constraints: BoxConstraints(
            minWidth: isImage ? 0 : 220,
            maxWidth: isImage ? 340 : 280,
          ),
          decoration: BoxDecoration(
            color: isImage
                ? Colors.transparent
                : colors.surfaceMuted.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(context.appRadii.md),
            border: isImage ? null : Border.all(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isImage)
                _buildImagePreview(context)
              else
                _buildFilePreview(context),
              if (!isImage)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    spacing.sm,
                    spacing.sm,
                    spacing.sm,
                    spacing.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              attachment.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '${formatBytes(attachment.sizeBytes)} • $actionLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: spacing.xs),
                      ChatTransferIndicator(transfer: transfer, isBusy: isBusy),
                    ],
                  ),
                ),
              if (isBusy && progress != null)
                LinearProgressIndicator(value: progress, minHeight: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview(BuildContext context) {
    if (localPath != null && localPath!.isNotEmpty) {
      return buildChatLocalImage(context, localPath!);
    }
    return _previewPlaceholder(
      context,
      isBusy ? Icons.downloading_rounded : Icons.image_outlined,
      isBusy ? 'Downloading image…' : 'Tap to open image',
    );
  }

  Widget _buildFilePreview(BuildContext context) {
    final isAudio = attachment.mimeType.startsWith('audio/');
    final extension = attachment.filename.contains('.')
        ? attachment.filename.split('.').last.toUpperCase()
        : 'FILE';
    return Container(
      height: 92,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: context.appColors.surface,
      child: Row(
        children: [
          Icon(
            isAudio ? Icons.mic_rounded : Icons.insert_drive_file_rounded,
            size: 36,
            color: context.appColors.primary,
          ),
          const SizedBox(width: 12),
          Text(
            extension,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: context.appColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewPlaceholder(
    BuildContext context,
    IconData icon,
    String label,
  ) {
    return Container(
      height: 180,
      width: double.infinity,
      color: context.appColors.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: context.appColors.textMuted),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
