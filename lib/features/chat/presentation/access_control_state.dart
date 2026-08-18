part of 'access_control_settings_page.dart';

class _AccessControlSettingsPageState extends State<AccessControlSettingsPage> {
  late final AccessControlRepository _repository;
  WorkspaceAccessSnapshot? _snapshot;
  AccessControlCatalog? _catalog;
  List<WorkspaceAccessRole> _roles = const [];
  List<WorkspaceAccessRoleAssignment> _assignments = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _canManage => _snapshot?.allows('roles.manage') == true;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _repository.fetchMyAccess();
      final results = await Future.wait<dynamic>([
        _repository.fetchCatalog(),
        _repository.fetchRoles(),
        _repository.fetchAssignments(),
      ]);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _catalog = results[0] as AccessControlCatalog;
        _roles = results[1] as List<WorkspaceAccessRole>;
        _assignments = results[2] as List<WorkspaceAccessRoleAssignment>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _buildView(context);
}
