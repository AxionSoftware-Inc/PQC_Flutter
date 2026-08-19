part of 'task_kpi_page.dart';

class _TaskKpiPageState extends State<TaskKpiPage> {
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _tasks = const [];
  List<Map<String, dynamic>> _assignees = const [];
  List<Map<String, dynamic>> _notifications = const [];
  List<Map<String, dynamic>> _kpiSummary = const [];
  Map<String, dynamic> _dashboard = const {};
  Map<String, dynamic> _report = const {};
  bool _dashboardLoading = true;
  int _unreadNotifications = 0;
  int? _nextOffset;
  bool _hasMore = false;
  final TextEditingController _searchController = TextEditingController();
  // Completed work stays out of the main inbox; it remains available through
  // the explicit "Tugallangan" filter.
  String _statusFilter = 'open';
  Timer? _searchDebounce;
  Timer? _refreshTimer;
  bool _loadInFlight = false;

  List<Map<String, dynamic>> get _visibleTasks {
    final query = _searchController.text.trim().toLowerCase();
    return _tasks.where((task) {
      final status = task['status'] as String? ?? 'todo';
      final title = (task['title'] as String? ?? '').toLowerCase();
      final description = (task['description'] as String? ?? '').toLowerCase();
      final matchesStatus = _statusFilter == 'open'
          ? status != 'done'
          : _statusFilter == 'all' || status == _statusFilter;
      return matchesStatus &&
          (query.isEmpty ||
              title.contains(query) ||
              description.contains(query));
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) unawaited(_load(background: true));
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
