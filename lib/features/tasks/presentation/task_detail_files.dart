part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member


extension _TaskDetailFileViews on _TaskDetailPageState {

  Widget _filesSection() {
    final spacing = context.appSpacing;
    final files = _fileEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Vazifa fayllari',
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
        if (_loadingActivities)
          const LinearProgressIndicator(minHeight: 2)
        else if (files.isEmpty)
          Text(
            'Hozircha fayl yo‘q.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ...files.map(_fileTile),
        SizedBox(height: spacing.xs),
        Text(
          'Fayllar vaqt bo‘yicha alohida saqlanadi; ularni vazifa ichidan ochish yoki yuklab olish mumkin.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.appColors.textMuted),
        ),
      ],
    );
  }

  Widget _fileTile(Map<String, dynamic> file) {
    final spacing = context.appSpacing;
    final filename = file['filename'] as String? ?? 'Fayl';
    final mime = _mimeType(filename);
    final isImage = mime.startsWith('image/');
    final id = (file['id'] as num?)?.toInt();
    final isOpening = id != null && _openingFileIds.contains(id);
    final author = file['author_name']?.toString();
    final date =
        file['activity_created_at']?.toString() ??
        file['created_at']?.toString() ??
        '';
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.xs),
      child: AppSurfaceCard(
        padding: EdgeInsets.symmetric(horizontal: spacing.xs, vertical: 2),
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: spacing.xs),
          leading: Icon(
            isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
          ),
          title: Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            isOpening
                ? 'Yuklanmoqda…'
                : [
                    _formatBytes(file['size_bytes'] as int? ?? 0),
                    if (author?.isNotEmpty == true) author!,
                    if (date.isNotEmpty) _formatDate(date),
                  ].join(' • '),
          ),
          trailing: isOpening
              ? const SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_new_rounded, size: 19),
          onTap: isOpening ? null : () => _openAttachment(file),
          onLongPress: isOpening ? null : () => _replyToAttachment(file),
        ),
      ),
    );
  }

  Widget _metaPill(BuildContext context, String label, IconData icon) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(context.appRadii.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.textMuted),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  // Legacy renderer retained for compatibility with old hot-reload sessions.
  // ignore: unused_element
  Widget _activityTile(Map<String, dynamic> activity) {
    final spacing = context.appSpacing;
    var body = activity['body'] as String? ?? '';
    final author = activity['author_name'] as String? ?? 'Tizim';
    final createdAt = activity['created_at']?.toString() ?? '';
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
    } else if (firstLine.startsWith('Faylga javob: ')) {
      replyKind ??= 'file';
      replyLabel ??= firstLine.substring('Faylga javob: '.length).trim();
      body = body.substring(firstLine.length).trim();
    } else if (firstLine.startsWith('Izohga javob: ')) {
      replyKind ??= 'comment';
      replyLabel ??= firstLine.substring('Izohga javob: '.length).trim();
      body = body.substring(firstLine.length).trim();
    }
    final isMine =
        (activity['author_id'] as num?)?.toInt() == widget.currentUserId;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.xs),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.84,
          ),
          child: GestureDetector(
            onLongPress: () => _showActivityActions(activity),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.sm,
                vertical: spacing.xs,
              ),
              decoration: BoxDecoration(
                color: isMine
                    ? context.appColors.chatMine
                    : context.appColors.surface,
                borderRadius: BorderRadius.circular(context.appRadii.lg),
                border: Border.all(
                  color: isMine
                      ? context.appColors.primary.withValues(alpha: 0.12)
                      : context.appColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          author,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isMine ? Colors.white : null,
                              ),
                        ),
                      ),
                      if (activity['is_pinned'] == true)
                        Icon(
                          Icons.push_pin_rounded,
                          size: 15,
                          color: isMine
                              ? Colors.white
                              : context.appColors.primary,
                        ),
                    ],
                  ),
                  if (replyLabel?.isNotEmpty == true) ...[
                    SizedBox(height: spacing.xs),
                    InkWell(
                      borderRadius: BorderRadius.circular(context.appRadii.sm),
                      onTap: replyKind == 'file' && replyId != null
                          ? () => _openAttachment({
                              'id': replyId,
                              'filename': replyLabel,
                            })
                          : null,
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: spacing.xs,
                          vertical: spacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.14)
                              : context.appColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(
                            context.appRadii.sm,
                          ),
                          border: Border(
                            left: BorderSide(
                              color: isMine
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : context.appColors.primary,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              replyKind == 'file'
                                  ? Icons.attach_file_rounded
                                  : Icons.reply_rounded,
                              size: 16,
                              color: isMine ? Colors.white : null,
                            ),
                            SizedBox(width: spacing.xs),
                            Expanded(
                              child: Text(
                                'Javob: $replyLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: isMine ? Colors.white : null,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (body.trim().isNotEmpty) ...[
                    SizedBox(height: spacing.xs),
                    Text(
                      body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isMine ? Colors.white : null,
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      createdAt.isEmpty ? '' : _formatDate(createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.72)
                            : context.appColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


}
