part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member, unused_element

extension _TaskCreateActions on _CreateTaskPageState {

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _dueAt ?? DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _dueAt == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(_dueAt!),
    );
    if (time == null) return;
    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _assigneeId == null) return;
    final oversized = _attachments.where(
      (file) => file.size > _CreateTaskPageState._maxAttachmentBytes,
    );
    if (oversized.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${oversized.first.name} hajmi 25 MB dan oshmasligi kerak.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final created = await widget.repository.post('/task-kpi/tasks', {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'assignee_id': _assigneeId,
        'priority': _priority,
        if (_dueAt != null) 'due_at': _dueAt!.toUtc().toIso8601String(),
      });
      if (_attachments.isNotEmpty && created is Map && created['id'] != null) {
        final taskId = (created['id'] as num).toInt();
        for (final attachment in _attachments) {
          await _uploadAttachment(taskId, attachment);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _uploadAttachment(int taskId, PlatformFile file) async {
    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      try {
        await widget.repository.multipartPost(
          '/task-kpi/tasks/$taskId/attachments',
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
        // Android content providers can expose a temporary path that is no
        // longer readable by the time the multipart stream starts. In that
        // case use the bytes loaded by FilePicker instead.
      }
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Fayl ma’lumotini o‘qib bo‘lmadi. Qayta tanlang.');
    }
    await widget.repository.multipartPost(
      '/task-kpi/tasks/$taskId/attachments',
      files: [http.MultipartFile.fromBytes('file', bytes, filename: file.name)],
    );
  }

}
