part of 'chat_list_page.dart';

class _ChatListPageState extends State<ChatListPage> {
  late final ChatHubController _controller;
  final TextEditingController _chatSearchController = TextEditingController();
  final TextEditingController _contactsSearchController =
      TextEditingController();
  int _selectedTabIndex = 0;
  bool _recoveryPromptShown = false;
  bool _notificationsEnabled = true;
  bool _notificationPreviewsEnabled = true;
  bool _readReceiptsEnabled = true;
  bool _typingIndicatorsEnabled = true;
  String _lastSeenVisibility = 'contacts';
  String _onlineVisibility = 'contacts';
  bool _accountSettingsHydrated = false;
  bool _isWorkspaceAdmin = false;
  final Set<int> _selectedConversationIds = <int>{};
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int get _taskKpiTabIndex => 2;
  int get _settingsTabIndex => _taskKpiModuleEnabled ? 3 : 2;
  int get _adminTabIndex => _settingsTabIndex + 1;
  bool get _showAdminTab => _rbacModuleEnabled && _isWorkspaceAdmin;

  @override
  void initState() {
    super.initState();
    final sessionUser = widget.sessionController.sessionUser!;
    _controller = ChatHubController(
      chatFacade: widget.chatFacade,
      cryptoCoreFacade: widget.cryptoCoreFacade,
      currentUserId: sessionUser.id,
      sessionUserProvider: () => widget.sessionController.sessionUser!,
      accountRepository: widget.accountRepository,
      database: widget.database,
    )..addListener(_onControllerChanged);
    _load();
    if (_rbacModuleEnabled) {
      _loadAdminAccess();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _chatSearchController.dispose();
    _contactsSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
