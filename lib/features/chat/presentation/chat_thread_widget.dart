import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';

/// A transport-neutral message used by both the normal conversation and
/// task-scoped threads. The `raw` value lets each adapter keep its own
/// controller/model without coupling the shared widget to an endpoint.
class ChatThreadMessage {
  const ChatThreadMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
    this.attachments = const [],
    this.isRead = false,
    this.isMine = false,
    this.canRetry = false,
    this.deliveryLabel = '',
    this.replyLabel,
    this.replyKind,
    this.replyId,
    this.isPinned = false,
    this.raw,
  });

  final int id;
  final int senderId;
  final String senderName;
  final String body;
  final DateTime createdAt;
  final List<ChatThreadAttachment> attachments;
  final bool isRead;
  final bool isMine;
  final bool canRetry;
  final String deliveryLabel;
  final String? replyLabel;
  final String? replyKind;
  final int? replyId;
  final bool isPinned;
  final Object? raw;
}

class ChatThreadAttachment {
  const ChatThreadAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    this.raw,
  });

  final int id;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final Object? raw;
}

typedef ChatThreadAttachmentBuilder =
    Widget Function(
      BuildContext context,
      ChatThreadAttachment attachment, {
      required ChatThreadMessage message,
      required bool showDeliveryOverlay,
    });

typedef ChatThreadFooterBuilder =
    Widget Function(BuildContext context, ChatThreadMessage message);

typedef ChatThreadBodyLabelBuilder = String Function(ChatThreadMessage message);

class ChatThreadWidget extends StatelessWidget {
  const ChatThreadWidget({
    super.key,
    required this.messages,
    required this.currentUserId,
    required this.isGroup,
    required this.attachmentBuilder,
    required this.footerBuilder,
    this.showSenderName = true,
    this.mineBackgroundColor,
    this.peerBackgroundColor,
    this.bodyLabelBuilder,
    this.controller,
    this.onRetry,
    this.onLongPressMessage,
    this.onLongPressAttachment,
    this.onTapReply,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
  });

  final List<ChatThreadMessage> messages;
  final int currentUserId;
  final bool isGroup;
  final bool showSenderName;
  final Color? mineBackgroundColor;
  final Color? peerBackgroundColor;
  final ChatThreadAttachmentBuilder attachmentBuilder;
  final ChatThreadFooterBuilder footerBuilder;
  final ChatThreadBodyLabelBuilder? bodyLabelBuilder;
  final ScrollController? controller;
  final Future<void> Function(ChatThreadMessage message)? onRetry;
  final Future<void> Function(ChatThreadMessage message)? onLongPressMessage;
  final Future<void> Function(ChatThreadAttachment attachment)?
  onLongPressAttachment;
  final Future<void> Function(ChatThreadMessage message)? onTapReply;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: messages.length,
      itemBuilder: (context, index) => _buildMessage(context, messages[index]),
    );
  }

  Widget _buildMessage(BuildContext context, ChatThreadMessage message) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final body = bodyLabelBuilder?.call(message) ?? message.body;
    final isMine = message.isMine || message.senderId == currentUserId;
    final isImageOnly =
        message.attachments.length == 1 &&
        message.attachments.single.mimeType.startsWith('image/') &&
        message.body.trim().isEmpty;
    final hasInlineFooter = !isImageOnly && body.trim().isNotEmpty;
    final messageKey = ValueKey(
      'thread-message-${message.id}-${message.createdAt.microsecondsSinceEpoch}',
    );
    return TweenAnimationBuilder<double>(
      key: messageKey,
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(
            isMine ? 12 * (1 - value) : -12 * (1 - value),
            5 * (1 - value),
          ),
          child: child,
        ),
      ),
      child: Align(
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onLongPress: onLongPressMessage == null
                      ? null
                      : () => onLongPressMessage!(message),
                  child: Container(
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
                          ? (mineBackgroundColor ?? colors.chatMine)
                          : (peerBackgroundColor ?? colors.chatPeer),
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
                      boxShadow: isImageOnly
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showSenderName &&
                            isGroup &&
                            !isMine &&
                            !isImageOnly)
                          Padding(
                            padding: EdgeInsets.only(bottom: spacing.xs),
                            child: Text(
                              message.senderName,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: colors.textMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        if (message.replyLabel?.isNotEmpty == true)
                          _replyPreview(context, message, isMine),
                        if (message.attachments.isNotEmpty)
                          Wrap(
                            spacing: spacing.xs,
                            runSpacing: spacing.xs,
                            children: message.attachments.map((attachment) {
                              final child = attachmentBuilder(
                                context,
                                attachment,
                                message: message,
                                showDeliveryOverlay: isImageOnly,
                              );
                              return onLongPressAttachment == null
                                  ? child
                                  : GestureDetector(
                                      onLongPress: () =>
                                          onLongPressAttachment!(attachment),
                                      child: child,
                                    );
                            }).toList(),
                          ),
                        if (message.attachments.isNotEmpty &&
                            message.body.trim().isNotEmpty)
                          SizedBox(height: spacing.sm),
                        if (body.trim().isNotEmpty)
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: body),
                                if (hasInlineFooter)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.baseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        left: spacing.sm,
                                      ),
                                      child: footerBuilder(context, message),
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
                          footerBuilder(context, message),
                        ],
                      ],
                    ),
                  ),
                ),
                if (message.canRetry && onRetry != null)
                  TextButton(
                    onPressed: () => onRetry!(message),
                    child: const Text('Qayta urinish'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _replyPreview(
    BuildContext context,
    ChatThreadMessage message,
    bool isMine,
  ) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.appSpacing.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(context.appRadii.sm),
        onTap: onTapReply == null ? null : () => onTapReply!(message),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: context.appSpacing.xs,
            vertical: context.appSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: isMine
                ? Colors.white.withValues(alpha: 0.14)
                : context.appColors.surfaceMuted,
            borderRadius: BorderRadius.circular(context.appRadii.sm),
            border: Border(
              left: BorderSide(
                color: isMine ? Colors.white : context.appColors.primary,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                message.replyKind == 'file'
                    ? Icons.attach_file_rounded
                    : Icons.reply_rounded,
                size: 15,
                color: isMine ? Colors.white : null,
              ),
              SizedBox(width: context.appSpacing.xs),
              Flexible(
                child: Text(
                  'Javob: ${message.replyLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isMine ? Colors.white : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
