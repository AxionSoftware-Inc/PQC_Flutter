part of 'admin_panel_page.dart';

class _AdminPanelPageState extends State<AdminPanelPage> {
  final TextEditingController _memberSearchController = TextEditingController();
  bool _loading = true;
  bool _isAdmin = false;
  String? _error;
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _members = const [];
  int _registeredUserCount = 0;
  String _memberStatusFilter = 'active';
  Timer? _registeredUsersTimer;

  @override
  void initState() {
    super.initState();
    _memberSearchController.addListener(() => setState(() {}));
    _load();
    _registeredUsersTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _isAdmin) unawaited(_refreshRegisteredUserCount());
    });
  }

  @override
  void dispose() {
    _registeredUsersTimer?.cancel();
    _memberSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
