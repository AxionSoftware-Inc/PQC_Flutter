part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TaskDetailActions on _TaskDetailPageState {
  Future<void> _openTaskChat() async {
    if (_openingTaskChat) return;
    final taskId = (task['id'] as num?)?.toInt();
    if (taskId == null) return;
    setState(() => _openingTaskChat = true);
    try {
      final conversation = await widget.repository.openTaskConversation(taskId);
      if (!mounted) return;
      await widget.onOpenTaskChat(
        conversation,
        'Vazifa • ${task['title']?.toString() ?? 'Vazifa'}',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vazifa chatini ochib bo‘lmadi: $error')),
      );
    } finally {
      if (mounted) setState(() => _openingTaskChat = false);
    }
  }

  Future<void> _loadActivities({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loadingActivities = true);
    try {
      final response = await widget.repository.get(
        '/task-kpi/tasks/${task['id']}/activity',
      );
      if (!mounted) return;
      setState(() {
        _activities = response is List
            ? response
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : const [];
        _activityError = null;
        _loadingActivities = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _activityError = error.toString();
        _loadingActivities = false;
      });
    }
  }

  Future<void> _pickActivityAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !mounted) return;
    final existing = _selectedAttachments
        .map((file) => '${file.name}:${file.size}')
        .toSet();
    final added = result.files
        .where((file) => file.size > 0)
        .where((file) => existing.add('${file.name}:${file.size}'))
        .toList();
    final oversized = added.where(
      (file) => file.size > _TaskDetailPageState._maxAttachmentBytes,
    );
    if (oversized.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${oversized.first.name} hajmi 25 MB dan oshmasligi kerak.',
          ),
        ),
      );
    }
    final valid = added
        .where((file) => file.size <= _TaskDetailPageState._maxAttachmentBytes)
        .toList();
    if (valid.isNotEmpty) {
      setState(() {
        _selectedAttachments = [..._selectedAttachments, ...valid];
      });
    }
  }

  Future<void> _sendUpdate() async {
    final body = _commentController.text.trim();
    if ((body.isEmpty && _selectedAttachments.isEmpty) || _sendingUpdate) {
      return;
    }
    setState(() => _sendingUpdate = true);
    try {
      if (body.isNotEmpty) {
        final payload = <String, dynamic>{'body': body};
        final replyId = (_replyTarget?['id'] as num?)?.toInt();
        final replyKind = _replyTarget?['kind']?.toString();
        final replyLabel = _replyTarget?['label']?.toString();
        if (replyId != null && replyKind != null) {
          final marker = replyKind == 'file' ? 'Faylga' : 'Izohga';
          final target = replyKind == 'file' ? 'file' : 'comment';
          payload['body'] =
              '$marker javob: $replyLabel [$target:$replyId]\n$body';
          payload['metadata'] = replyKind == 'file'
              ? {'reply_to_attachment_id': replyId}
              : {'reply_to_activity_id': replyId};
        }
        await widget.repository.post(
          '/task-kpi/tasks/${task['id']}/activity',
          payload,
        );
      }
      for (final file in _selectedAttachments) {
        await _uploadActivityAttachment(file);
      }
      _commentController.clear();
      if (mounted) {
        setState(() {
          _selectedAttachments = const [];
          _replyTarget = null;
        });
      }
      await _loadActivities();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _sendingUpdate = false);
    }
  }

  void _replyToAttachment(Map<String, dynamic> file) {
    setState(() {
      _replyTarget = {
        'id': file['id'],
        'kind': 'file',
        'label': file['filename'] ?? 'Fayl',
      };
    });
    _tabController.animateTo(1);
  }

  void _replyToActivity(Map<String, dynamic> activity) {
    final body = activity['body']?.toString().trim() ?? '';
    if (body.isEmpty) return;
    setState(() {
      _replyTarget = {
        'id': activity['id'],
        'kind': 'text',
        'label': body.split('\n').first,
      };
    });
    _tabController.animateTo(1);
  }

  List<Map<String, dynamic>> get _pinnedActivities => _activities
      .where((activity) => activity['is_pinned'] == true)
      .toList(growable: false);

  Future<void> _togglePin(Map<String, dynamic> activity) async {
    final id = (activity['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await widget.repository.post(
        '/task-kpi/tasks/${task['id']}/activity/$id/pin',
        {'pinned': activity['is_pinned'] != true},
      );
      await _loadActivities(silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pin holatini o‘zgartirib bo‘lmadi: $error')),
      );
    }
  }

  Future<void> _showActivityActions(Map<String, dynamic> activity) async {
    final body = activity['body']?.toString().trim() ?? '';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Javob yozish'),
              onTap: () {
                Navigator.pop(sheetContext);
                _replyToActivity(activity);
              },
            ),
            ListTile(
              leading: Icon(
                activity['is_pinned'] == true
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
              ),
              title: Text(
                activity['is_pinned'] == true
                    ? 'Pindan chiqarish'
                    : 'Pin qilish',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _togglePin(activity);
              },
            ),
            if (body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Matnni nusxalash'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: body));
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachment(Map<String, dynamic> file) async {
    final id = (file['id'] as num?)?.toInt();
    if (id == null || _openingFileIds.contains(id)) return;
    setState(() => _openingFileIds.add(id));
    try {
      await widget.onDownloadAttachment(file);
    } finally {
      if (mounted) setState(() => _openingFileIds.remove(id));
    }
  }

  Future<void> _uploadActivityAttachment(PlatformFile file) async {
    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      try {
        await widget.repository.multipartPost(
          '/task-kpi/tasks/${task['id']}/attachments',
          files: [
            await http.MultipartFile.fromPath(
              'file',
              path,
              filename: file.name,
            ),
          ],
        );
        return;
      } on FileSystemException {
        // Android content-provider paths can expire; use picker bytes below.
      }
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Fayl ma’lumotini o‘qib bo‘lmadi. Qayta tanlang.');
    }
    await widget.repository.multipartPost(
      '/task-kpi/tasks/${task['id']}/attachments',
      files: [http.MultipartFile.fromBytes('file', bytes, filename: file.name)],
    );
  }
}
