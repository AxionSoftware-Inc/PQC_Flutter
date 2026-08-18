part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TaskDetailComments on _TaskDetailPageState {
  Widget _commentsSection() {
    final comments = _commentActivities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Izohlar',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Yangilash',
              onPressed: _loadingActivities ? null : _loadActivities,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        if (_pinnedActivities.isNotEmpty) ...[
          SizedBox(height: context.appSpacing.xs),
          _pinnedActivityBar(),
        ],
        if (_loadingActivities)
          const LinearProgressIndicator(minHeight: 2)
        else if (_activityError != null)
          AppStatusBanner(
            message: _activityError!,
            tone: AppStatusTone.danger,
            action: TextButton(
              onPressed: _loadActivities,
              child: const Text('Qayta urinish'),
            ),
          )
        else if (comments.isEmpty)
          Text(
            'Hozircha izoh yo‘q.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ChatThreadWidget(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            messages: comments.map(_toTaskThreadMessage).toList(),
            currentUserId: widget.currentUserId,
            isGroup: true,
            showSenderName: false,
            mineBackgroundColor: context.appColors.primary,
            peerBackgroundColor: context.appColors.surfaceMuted,
            attachmentBuilder:
                (
                  context,
                  attachment, {
                  required message,
                  required showDeliveryOverlay,
                }) => _taskThreadAttachment(attachment),
            footerBuilder: (context, message) => _taskThreadFooter(message),
            onLongPressMessage: (message) async {
              final activity = message.raw as Map<String, dynamic>;
              await _showActivityActions(activity);
            },
            onLongPressAttachment: (attachment) async {
              final raw = attachment.raw as Map<String, dynamic>;
              _replyToAttachment(raw);
            },
            onTapReply: (message) async {
              if (message.replyKind == 'file' && message.replyId != null) {
                await _openAttachment({
                  'id': message.replyId,
                  'filename': message.replyLabel ?? 'Fayl',
                });
              }
            },
          ),
      ],
    );
  }

  ChatThreadMessage _toTaskThreadMessage(Map<String, dynamic> activity) {
    var body = activity['body']?.toString() ?? '';
    final authorId = _activityAuthorId(activity);
    final metadata = (activity['metadata'] as Map?)?.cast<String, dynamic>();
    var replyLabel =
        metadata?['reply_to_filename']?.toString() ??
        metadata?['reply_to_text']?.toString();
    var replyKind = metadata?['reply_to_attachment_id'] != null
        ? 'file'
        : metadata?['reply_to_activity_id'] != null
        ? 'comment'
        : null;
    var replyId =
        (metadata?['reply_to_attachment_id'] as num?)?.toInt() ??
        (metadata?['reply_to_activity_id'] as num?)?.toInt();
    final firstLine = body.split('\n').first.trim();
    final marker = RegExp(
      r'^(Faylga|Izohga) javob: (.+?) \[(file|comment):(\d+)\]$',
    ).firstMatch(firstLine);
    if (marker != null) {
      replyKind ??= marker.group(3);
      replyId ??= int.tryParse(marker.group(4)!);
      replyLabel ??= marker.group(2)?.trim();
      body = body.substring(firstLine.length).trim();
    }
    final rawAttachments = (activity['attachments'] as List?) ?? const [];
    return ChatThreadMessage(
      id: (activity['id'] as num?)?.toInt() ?? 0,
      senderId: authorId,
      senderName: activity['author_name']?.toString() ?? 'Tizim',
      body: body.startsWith('Fayl biriktirdi:') ? '' : body,
      createdAt:
          DateTime.tryParse(activity['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isMine: authorId == widget.currentUserId,
      isPinned: activity['is_pinned'] == true,
      replyLabel: replyLabel,
      replyKind: replyKind,
      replyId: replyId,
      attachments: rawAttachments.whereType<Map>().map((raw) {
        return ChatThreadAttachment(
          id: (raw['id'] as num?)?.toInt() ?? 0,
          filename: raw['filename']?.toString() ?? 'Fayl',
          mimeType: _mimeType(raw['filename']?.toString() ?? ''),
          sizeBytes: (raw['size_bytes'] as num?)?.toInt() ?? 0,
          raw: Map<String, dynamic>.from(raw),
        );
      }).toList(),
      raw: activity,
    );
  }

  int _activityAuthorId(Map<String, dynamic> activity) {
    for (final key in const [
      'author_id',
      'created_by_id',
      'user_id',
      'actor_id',
    ]) {
      final value = activity[key];
      final parsed = value is num ? value.toInt() : int.tryParse('$value');
      if (parsed != null && parsed > 0) return parsed;
    }
    final author = activity['author'];
    if (author is Map) {
      final value = author['id'];
      final parsed = value is num ? value.toInt() : int.tryParse('$value');
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0;
  }

  Widget _taskThreadAttachment(ChatThreadAttachment attachment) {
    final raw = attachment.raw as Map<String, dynamic>;
    final isImage = attachment.mimeType.startsWith('image/');
    return InkWell(
      onTap: () => _openAttachment(raw),
      borderRadius: BorderRadius.circular(context.appRadii.sm),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: EdgeInsets.symmetric(
          horizontal: context.appSpacing.sm,
          vertical: context.appSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isImage
              ? Colors.transparent
              : context.appColors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(context.appRadii.sm),
          border: isImage ? null : Border.all(color: context.appColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
              size: 18,
              color: context.appColors.primary,
            ),
            SizedBox(width: context.appSpacing.xs),
            Flexible(
              child: Text(
                attachment.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (attachment.sizeBytes > 0) ...[
              SizedBox(width: context.appSpacing.xs),
              Text(
                _formatBytes(attachment.sizeBytes),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.appColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _taskThreadFooter(ChatThreadMessage message) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatDate(message.createdAt.toIso8601String()),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: message.isMine
                ? Colors.white.withValues(alpha: 0.72)
                : context.appColors.textMuted,
          ),
        ),
        if (message.isPinned) ...[
          SizedBox(width: context.appSpacing.xs),
          Icon(
            Icons.push_pin_rounded,
            size: 14,
            color: message.isMine ? Colors.white : context.appColors.primary,
          ),
        ],
      ],
    );
  }

  Widget _pinnedActivityBar() {
    final pinned = _pinnedActivities.first;
    final preview = pinned['body']?.toString().split('\n').last.trim() ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(context.appRadii.md),
      onTap: () => _showActivityActions(pinned),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: context.appSpacing.sm,
          vertical: context.appSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: context.appColors.surfaceMuted,
          borderRadius: BorderRadius.circular(context.appRadii.md),
          border: Border.all(color: context.appColors.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.push_pin_rounded,
              size: 17,
              color: context.appColors.primary,
            ),
            SizedBox(width: context.appSpacing.xs),
            Expanded(
              child: Text(
                preview.isEmpty ? 'Biriktirilgan xabar' : preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
