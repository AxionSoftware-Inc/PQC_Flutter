import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../application/chat_services.dart';
import '../../security/key_verification_service.dart';
import '../../transfers/application/attachment_transfer.dart';
import 'chat_local_image.dart';

class ChatComposerActionButton extends StatelessWidget {
  const ChatComposerActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(36),
        maximumSize: const Size.square(36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class ChatComposerSendButton extends StatelessWidget {
  const ChatComposerSendButton({
    super.key,
    required this.isSending,
    required this.onPressed,
  });

  final bool isSending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: isSending
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.arrow_upward_rounded, size: 18),
    );
  }
}

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
                      _TransferIndicator(transfer: transfer, isBusy: isBusy),
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

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.isGrouped = false,
    this.reaction,
    required this.maxWidth,
    required this.attachmentBuilder,
    required this.statusLabel,
    required this.formatTime,
    this.onRetry,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isGrouped;
  final String? reaction;
  final double maxWidth;
  final Widget Function(ChatAttachment attachment) attachmentBuilder;
  final String Function(ChatMessage message) statusLabel;
  final String Function(DateTime value) formatTime;
  final VoidCallback? onRetry;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final isDecryptNeedsRestore =
        message.body == ChatCryptoService.decryptNeedsBackupRestoreMarker ||
        message.body == ChatCryptoService.decryptKeyMissingMarker;
    final isDecryptError = message.body == ChatCryptoService.decryptErrorMarker;
    final bodyColor = isMine ? Colors.white : null;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(
            left: spacing.xs,
            right: spacing.xs,
            top: isGrouped ? 1 : spacing.xs,
            bottom: spacing.xs,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.md,
                      vertical: spacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: isMine ? colors.chatMine : colors.chatPeer,
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
                      border: Border.all(
                        color: isMine
                            ? colors.primary.withValues(alpha: 0.16)
                            : colors.border,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMine && !isGrouped) ...[
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
                                .map(attachmentBuilder)
                                .toList(),
                          ),
                          if (message.body.trim().isNotEmpty)
                            SizedBox(height: spacing.sm),
                        ],
                        if (isDecryptNeedsRestore)
                          _MessageBody(
                            text:
                                'Historical decrypt unavailable on this device. Restore backup to read this message.',
                            color: bodyColor,
                          )
                        else if (isDecryptError)
                          _MessageBody(
                            text: 'Unable to decrypt this message.',
                            color: bodyColor,
                          )
                        else if (message.body.trim().isNotEmpty)
                          _MessageBody(text: message.body, color: bodyColor),
                        if (_extractUrl(message.body) != null)
                          _LinkPreviewCard(url: _extractUrl(message.body)!),
                        SizedBox(height: spacing.xs),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: spacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (message.deliveryState !=
                                  MessageDeliveryState.sent)
                                Text(
                                  statusLabel(message),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: isMine
                                            ? Colors.white.withValues(
                                                alpha: 0.72,
                                              )
                                            : colors.textMuted,
                                      ),
                                ),
                              Text(
                                formatTime(message.createdAt),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: isMine
                                          ? Colors.white.withValues(alpha: 0.68)
                                          : colors.textMuted,
                                    ),
                              ),
                              if (isMine)
                                Icon(
                                  message.deliveryState ==
                                          MessageDeliveryState.sent
                                      ? Icons.done_all_rounded
                                      : Icons.schedule_rounded,
                                  size: 14,
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                            ],
                          ),
                        ),
                        if (reaction != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              reaction!,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (message.canRetry)
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _extractUrl(String text) {
  final match = RegExp(
    r'(https?://[^\s]+)',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(1);
}

class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.isNotEmpty == true ? uri!.host : url;
    return Container(
      margin: EdgeInsets.only(top: context.appSpacing.xs),
      padding: EdgeInsets.all(context.appSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.appRadii.sm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 20, color: context.appColors.primary),
          SizedBox(width: context.appSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.text, required this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: color, height: 1.35),
    );
  }
}

class _TransferIndicator extends StatelessWidget {
  const _TransferIndicator({required this.transfer, required this.isBusy});

  final AttachmentTransferState? transfer;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    if (isBusy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (transfer?.status == AttachmentTransferStatus.completed) {
      return Icon(Icons.check_circle_rounded, color: context.appColors.success);
    }
    if (transfer?.status == AttachmentTransferStatus.failed) {
      return Icon(Icons.refresh_rounded, color: context.appColors.danger);
    }
    return Icon(Icons.download_rounded, color: context.appColors.primary);
  }
}
