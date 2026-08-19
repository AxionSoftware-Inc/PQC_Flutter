part of 'task_kpi_page.dart';

class _CreateTaskPage extends StatefulWidget {
  const _CreateTaskPage({required this.repository, required this.assignees});

  final TaskKpiRepository repository;
  final List<Map<String, dynamic>> assignees;

  @override
  State<_CreateTaskPage> createState() => _CreateTaskPageState();
}

class _CreateTaskPageState extends State<_CreateTaskPage> {
  static const _maxAttachmentBytes = 25 * 1024 * 1024;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _assigneeId;
  String _priority = 'normal';
  DateTime? _dueAt;
  List<PlatformFile> _attachments = const [];
  bool _saving = false;

  /// The assignee endpoint is scoped by workspace, but older server builds
  /// could return the same member more than once after a role change. Keep the
  /// picker deterministic and show each employee only once.
  List<Map<String, dynamic>> get _uniqueAssignees {
    final byMemberId = <int, Map<String, dynamic>>{};
    for (final member in widget.assignees) {
      final id = (member['member_id'] as num?)?.toInt();
      if (id != null) {
        byMemberId.putIfAbsent(id, () => member);
      }
    }
    return byMemberId.values.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    final assignees = _uniqueAssignees;
    if (assignees.isNotEmpty) {
      _assigneeId = (assignees.first['member_id'] as num?)?.toInt();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

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
      (file) => file.size > _maxAttachmentBytes,
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
      final created = await widget.repository.createTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        assigneeId: _assigneeId!,
        priority: _priority,
        dueAt: _dueAt,
      );
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
    await widget.repository.uploadTaskAttachment(
      taskId,
      path: file.path,
      bytes: file.bytes,
      filename: file.name,
    );
  }

  @override
  Widget build(BuildContext context) => _buildView(context);
}
