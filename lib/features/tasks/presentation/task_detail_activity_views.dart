part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member


extension _TaskDetailActivityViews on _TaskDetailPageState {

  Widget _activityComposer() {
    final spacing = context.appSpacing;
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(context.appRadii.lg),
        border: Border.all(color: context.appColors.border),
      ),
      padding: EdgeInsets.fromLTRB(
        spacing.sm,
        spacing.xs,
        spacing.xs,
        spacing.xs,
      ),
      child: Column(
        children: [
          if (_replyTarget != null)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: spacing.xs),
              padding: EdgeInsets.symmetric(
                horizontal: spacing.xs,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: context.appColors.surfaceMuted,
                borderRadius: BorderRadius.circular(context.appRadii.sm),
                border: Border(
                  left: BorderSide(color: context.appColors.primary, width: 3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded, size: 17),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: Text(
                      '${_replyTarget!['kind'] == 'file' ? 'Faylga' : 'Izohga'} javob: ${_replyTarget!['label'] ?? 'Tanlangan matn'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _sendingUpdate
                        ? null
                        : () => setState(() => _replyTarget = null),
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !_sendingUpdate,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Izoh yozing…',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Rasm yoki fayl biriktirish',
                onPressed: _sendingUpdate ? null : _pickActivityAttachments,
                icon: const Icon(Icons.attach_file_rounded),
              ),
              IconButton.filled(
                tooltip: 'Yuborish',
                onPressed: _sendingUpdate ? null : _sendUpdate,
                icon: _sendingUpdate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded, size: 18),
              ),
            ],
          ),
          if (_selectedAttachments.isNotEmpty)
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedAttachments.length,
                separatorBuilder: (_, _) => SizedBox(width: spacing.xs),
                itemBuilder: (context, index) {
                  final file = _selectedAttachments[index];
                  return InputChip(
                    label: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: _sendingUpdate
                        ? null
                        : () => setState(() {
                            _selectedAttachments = [
                              ..._selectedAttachments.sublist(0, index),
                              ..._selectedAttachments.sublist(index + 1),
                            ];
                          }),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _mimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    return 'application/octet-stream';
  }

}
