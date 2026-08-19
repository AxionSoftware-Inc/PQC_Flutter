part of 'task_kpi_page.dart';

class _TaskDetailPage extends StatefulWidget {
  const _TaskDetailPage({
    required this.repository,
    required this.currentUserId,
    required this.onOpenTaskChat,
    required this.task,
    required this.canReview,
    required this.onAdvance,
    required this.onReview,
    required this.onDownloadAttachment,
  });

  final TaskKpiRepository repository;
  final int currentUserId;
  final Future<void> Function(Conversation conversation, String title)
  onOpenTaskChat;
  final Map<String, dynamic> task;
  final bool canReview;
  final Future<void> Function() onAdvance;
  final Future<void> Function(bool accepted) onReview;
  final Future<void> Function(Map<String, dynamic> attachment)
  onDownloadAttachment;

  @override
  State<_TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<_TaskDetailPage>
    with SingleTickerProviderStateMixin {
  static const _maxAttachmentBytes = 25 * 1024 * 1024;
  final TextEditingController _commentController = TextEditingController();
  late final TabController _tabController;
  List<Map<String, dynamic>> _activities = const [];
  List<PlatformFile> _selectedAttachments = const [];
  Map<String, dynamic>? _replyTarget;
  final Set<int> _openingFileIds = <int>{};
  Timer? _activityRefreshTimer;
  bool _loadingActivities = true;
  bool _sendingUpdate = false;
  bool _openingTaskChat = false;
  String? _activityError;

  Map<String, dynamic> get task => widget.task;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    unawaited(_loadActivities());
    _activityRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && !_loadingActivities) {
        unawaited(_loadActivities(silent: true));
      }
    });
  }

  void _onTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    _activityRefreshTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  String _statusLabel(String value) => switch (value) {
    'accepted' => 'Qabul qilingan',
    'in_progress' => 'Jarayonda',
    'submitted' => 'Rahbar tekshiradi',
    'done' => 'Tugatildi',
    'returned' => 'Qayta ishlash kerak',
    'cancelled' => 'Bekor qilingan',
    _ => 'Yangi',
  };

  String _priorityLabel(String value) => switch (value) {
    'low' => 'Past',
    'high' => 'Yuqori',
    'urgent' => 'Shoshilinch',
    _ => 'Oddiy',
  };

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    return '${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
