import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/chat_message.dart';
import '../application/chat_services.dart';

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
    this.onTap,
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
  final VoidCallback? onTap;
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
        onTap: onTap,
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
