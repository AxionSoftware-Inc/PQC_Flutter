part of 'chat_page.dart';

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final ChatConversationController _controller;
  final LocalUiPreferencesStore _preferencesStore = LocalUiPreferencesStore();
  List<_SelectedAttachment> _selectedAttachments = const [];
  Timer? _draftDebounce;
  bool _keepDrafts = true;
  bool _showSecurityDetails = false;
  bool _showTransferDetails = false;
  final Map<int, String> _downloadedAttachmentPaths = <int, String>{};
  final Set<int> _imagePreviewDownloadsInFlight = <int>{};
  final Set<int> _imagePreviewDownloadFailures = <int>{};
  bool _isImagePreviewQueueRunning = false;
  int _lastMessageCount = 0;
  bool _hasRenderedMessages = false;

  @override
  void initState() {
    super.initState();
    _controller = ChatConversationController(
      chatFacade: widget.chatFacade,
      currentUserId: widget.currentUserId,
      conversation: widget.conversation,
    )..addListener(_onControllerChanged);
    _messageController.addListener(_queueDraftSave);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _draftDebounce?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}
