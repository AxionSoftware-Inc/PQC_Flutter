import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/app_localization.dart';
import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_ui_preferences_store.dart';
import '../../../app/theme_controller.dart';
import '../../auth/session_controller.dart';
import '../../chat/application/chat_facade.dart';
import '../../crypto/durability/crypto_core_facade.dart';
import 'chat_hub_controller.dart';
import 'chat_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({
    super.key,
    required this.sessionController,
    required this.chatFacade,
    required this.cryptoCoreFacade,
    required this.themeController,
    required this.apiClient,
  });

  final SessionController sessionController;
  final ChatFacade chatFacade;
  final CryptoCoreFacade cryptoCoreFacade;
  final AppThemeController themeController;
  final ApiClient apiClient;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

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
  final Set<int> _selectedConversationIds = <int>{};
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    final sessionUser = widget.sessionController.sessionUser!;
    _controller = ChatHubController(
      chatFacade: widget.chatFacade,
      cryptoCoreFacade: widget.cryptoCoreFacade,
      currentUserId: sessionUser.id,
      sessionUserProvider: () => widget.sessionController.sessionUser!,
      apiClient: widget.apiClient,
    )..addListener(_onControllerChanged);
    _load();
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

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final accountSettings = _controller.accountSettings;
    if (!_accountSettingsHydrated && accountSettings.isNotEmpty) {
      _notificationsEnabled =
          accountSettings['notifications_enabled'] as bool? ?? true;
      _notificationPreviewsEnabled =
          accountSettings['notification_previews'] as bool? ?? true;
      _readReceiptsEnabled =
          accountSettings['read_receipts_enabled'] as bool? ?? true;
      _typingIndicatorsEnabled =
          accountSettings['typing_indicators_enabled'] as bool? ?? true;
      _lastSeenVisibility =
          accountSettings['last_seen_visibility'] as String? ?? 'contacts';
      _onlineVisibility =
          accountSettings['online_visibility'] as String? ?? 'contacts';
      _accountSettingsHydrated = true;
    }
    final chatQuery = _controller.chatState.preferences.searchQuery;
    if (_chatSearchController.text != chatQuery) {
      _chatSearchController.value = TextEditingValue(
        text: chatQuery,
        selection: TextSelection.collapsed(offset: chatQuery.length),
      );
    }
    final contactsQuery = _controller.contactsState.searchQuery;
    if (_contactsSearchController.text != contactsQuery) {
      _contactsSearchController.value = TextEditingValue(
        text: contactsQuery,
        selection: TextSelection.collapsed(offset: contactsQuery.length),
      );
    }
    setState(() {});
  }

  Future<void> _load() async {
    try {
      await _controller.load();
      await _syncServerRecovery();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.sessionController.invalidateSession();
      }
    }
  }

  Future<void> _syncServerRecovery() async {
    if (_recoveryPromptShown || !mounted) return;
    _recoveryPromptShown = true;
    await _controller.syncEnterpriseRecoveryManifest();
    if (mounted) await _controller.refresh();
  }

  Future<void> _showPendingRecoveryApprovals() async {
    final approvals = await _controller.pendingRecoveryApprovals();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Tarixni tiklash so‘rovlari'),
              subtitle: Text(
                'Faqat o‘zingiz taniydigan qurilmani tasdiqlang. Ruxsat muddati avtomatik tugaydi.',
              ),
            ),
            if (approvals.isEmpty)
              const ListTile(title: Text('Kutilayotgan so‘rov yo‘q')),
            for (final approval in approvals)
              ListTile(
                leading: const Icon(Icons.devices_other_outlined),
                title: Text(
                  approval['requesting_device_id'] as String? ??
                      'Yangi qurilma',
                ),
                subtitle: Text(
                  'So‘ralgan vaqt: ${approval['created_at'] ?? ''}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Rad etish',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () async {
                        await _controller.decideRecoveryApproval(
                          approvalId: approval['id'] as int,
                          approved: false,
                        );
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                    IconButton(
                      tooltip: 'Tasdiqlash',
                      icon: const Icon(Icons.check_rounded),
                      onPressed: () async {
                        await _controller.decideRecoveryApproval(
                          approvalId: approval['id'] as int,
                          approved: true,
                        );
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<String?> _showRecoveryPinDialog({required bool hasServerBackup}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          hasServerBackup
              ? 'Chat tarixini tiklash'
              : 'Chat tarixini himoyalash',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasServerBackup
                  ? 'Bu akkauntda shifrlangan tiklash nusxasi mavjud. Eski xabarlarni ochish uchun tiklash PIN kodini kiriting.'
                  : 'Tiklash PIN kodini yarating. U chat kalitlarini himoyalaydi va qayta o‘rnatishdan keyin tarixni tiklashga yordam beradi.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: const InputDecoration(labelText: 'Tiklash PIN kodi'),
            ),
          ],
        ),
        actions: [
          if (hasServerBackup)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Keyinroq'),
            ),
          FilledButton(
            onPressed: () {
              final pin = controller.text.trim();
              if (pin.length < 6) return;
              Navigator.of(dialogContext).pop(pin);
            },
            child: Text(hasServerBackup ? 'Tiklash' : 'Zaxirani saqlash'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _refresh() async {
    try {
      await _controller.refresh();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.sessionController.invalidateSession();
      }
    }
  }

  Future<void> _openConversation({
    required Conversation conversation,
    required String title,
    String avatarUrl = '',
    String roleLabel = '',
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          currentUserId: widget.sessionController.sessionUser!.id,
          conversation: conversation,
          title: title,
          avatarUrl: avatarUrl,
          roleLabel: roleLabel,
          chatFacade: widget.chatFacade,
          cryptoCoreFacade: widget.cryptoCoreFacade,
          onUnauthorized: widget.sessionController.invalidateSession,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openConversationItem(ConversationListItemState item) {
    return _openConversation(
      conversation: item.conversation,
      title: item.title,
      avatarUrl: item.avatarUrl,
      roleLabel: item.roleLabel,
    );
  }

  Future<void> _openContact(AppUser user) async {
    try {
      final conversation = await _controller.startChatForUser(user);
      if (!mounted) {
        return;
      }
      await _openConversation(
        conversation: conversation,
        title: user.displayName,
        avatarUrl: user.avatarUrl,
        roleLabel: user.roleLabel,
      );
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.sessionController.invalidateSession();
        return;
      }
      if (!mounted) {
        return;
      }
      _showMessage(error.toString(), tone: AppStatusTone.danger);
    }
  }

  Future<void> _showConversationActions(ConversationListItemState item) async {
    final spacing = context.appSpacing;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  title: Text(
                    item.isPinned ? 'Chatni bo‘shatish' : 'Chatni mahkamlash',
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _controller.togglePinned(item.conversation.id);
                  },
                ),
                ListTile(
                  leading: Icon(
                    item.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  title: Text(
                    item.isArchived ? 'Arxivdan chiqarish' : 'Arxivlash',
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _controller.toggleArchived(item.conversation.id);
                  },
                ),
                ListTile(
                  leading: Icon(
                    item.isUnread
                        ? Icons.mark_chat_read_outlined
                        : Icons.mark_chat_unread_outlined,
                  ),
                  title: Text(
                    item.isUnread ? 'O‘qilgan qilish' : 'O‘qilmagan qilish',
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _controller.toggleManualUnread(item.conversation.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showContactDetails(ContactListItemState item) async {
    final detail = _controller.buildContactDetailState(item.user);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ContactDetailPage(
          item: item,
          detail: detail,
          onStartChat: item.isCurrentUser
              ? null
              : () async {
                  await _openContact(item.user);
                },
          onVerify: detail.canVerify
              ? () async {
                  await _controller.verifyContact(item.user);
                  if (!mounted) {
                    return;
                  }
                  _showMessage(
                    'Kontakt kaliti tasdiqlandi.',
                    tone: AppStatusTone.success,
                  );
                }
              : null,
          onRoleChanged: item.user.canManageRole
              ? (role) async {
                  await _controller.updateContactRole(item.user, role);
                }
              : null,
        ),
      ),
    );
  }

  Future<void> _switchWorkspace(int workspaceId) async {
    await widget.sessionController.switchWorkspace(workspaceId);
    widget.chatFacade.switchWorkspaceContext(workspaceId);
    await _load();
  }

  Future<void> _showEditProfile() async {
    final session = widget.sessionController.sessionUser!;
    final nameController = TextEditingController(text: session.displayName);
    PlatformFile? selectedAvatar;
    var isSaving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                context.appSpacing.lg,
                context.appSpacing.xs,
                context.appSpacing.lg,
                MediaQuery.viewInsetsOf(sheetContext).bottom +
                    context.appSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: isSaving
                        ? null
                        : () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: const [
                                'jpg',
                                'jpeg',
                                'png',
                                'webp',
                              ],
                              withData: true,
                            );
                            final file = result?.files.singleOrNull;
                            if (file == null) {
                              return;
                            }
                            if (file.size > 5 * 1024 * 1024) {
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Rasm hajmi 5 MB dan oshmasligi kerak.',
                                      ),
                                    ),
                                  );
                              }
                              return;
                            }
                            setSheetState(() => selectedAvatar = file);
                          },
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        if (selectedAvatar?.bytes != null)
                          ClipOval(
                            child: SizedBox.square(
                              dimension: 84,
                              child: Image.memory(
                                selectedAvatar!.bytes!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        else
                          AppAvatar(
                            label: session.displayName,
                            imageUrl: session.avatarUrl,
                            radius: 42,
                          ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: context.appColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: context.appColors.surface,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.photo_camera_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: context.appSpacing.md),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Ism va familiya',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  SizedBox(height: context.appSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final name = nameController.text.trim();
                              if (name.length < 2) {
                                return;
                              }
                              setSheetState(() => isSaving = true);
                              try {
                                await widget.sessionController.updateProfile(
                                  displayName: name,
                                  avatarBytes: selectedAvatar?.bytes,
                                  avatarFilename: selectedAvatar?.name ?? '',
                                );
                                await _controller.refresh();
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              } catch (error) {
                                if (sheetContext.mounted) {
                                  ScaffoldMessenger.of(sheetContext)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(
                                      SnackBar(content: Text(error.toString())),
                                    );
                                  setSheetState(() => isSaving = false);
                                }
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Saqlash'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(nameController.dispose);
  }

  // ignore: unused_element
  Future<void> _showExportBackupSheet() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final spacing = context.appSpacing;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.lg,
              spacing.lg,
              spacing.lg + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  title: 'Shifrlangan zaxirani eksport qilish',
                  subtitle:
                      'Recovery passphrase bilan historical decrypt backup yaratiladi.',
                ),
                SizedBox(height: spacing.lg),
                AppTextField(
                  controller: controller,
                  labelText: 'Tiklash maxfiy iborasi',
                ),
                SizedBox(height: spacing.lg),
                AppPrimaryButton(
                  onPressed: () async {
                    final passphrase = controller.text.trim();
                    if (passphrase.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop();
                    final blob = await _controller.exportBackup(passphrase);
                    if (!mounted) {
                      return;
                    }
                    await _showBlobSheet(
                      title: 'Serverga saqlandi: encrypted backup blob',
                      blob: blob,
                    );
                  },
                  label: const Text('Zaxira yaratish'),
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
  }

  // ignore: unused_element
  Future<void> _showImportBackupSheet() async {
    final passphraseController = TextEditingController();
    final blobController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final spacing = context.appSpacing;
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.lg,
              spacing.lg,
              spacing.lg + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  title: 'Shifrlangan zaxirani import qilish',
                  subtitle:
                      'Old historical decrypt capability qayta tiklanadi.',
                ),
                SizedBox(height: spacing.lg),
                AppTextField(
                  controller: passphraseController,
                  labelText: 'Tiklash maxfiy iborasi',
                ),
                SizedBox(height: spacing.md),
                AppTextField(
                  controller: blobController,
                  labelText: 'Shifrlangan zaxira ma’lumoti',
                  maxLines: 8,
                  minLines: 6,
                ),
                SizedBox(height: spacing.md),
                AppSecondaryButton(
                  onPressed: () async {
                    final blob = await _controller.downloadServerBackup();
                    if (blob == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Serverda backup topilmadi.'),
                          ),
                        );
                      }
                      return;
                    }
                    blobController.text = blob;
                  },
                  label: const Text('Serverdan zaxirani yuklash'),
                ),
                SizedBox(height: spacing.lg),
                AppPrimaryButton(
                  onPressed: () async {
                    final passphrase = passphraseController.text.trim();
                    final blob = blobController.text.trim();
                    if (passphrase.isEmpty || blob.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop();
                    await _controller.importBackup(
                      recoveryPassphrase: passphrase,
                      encryptedBlob: blob,
                    );
                  },
                  label: const Text('Zaxirani tiklash'),
                ),
              ],
            ),
          ),
        );
      },
    );
    passphraseController.dispose();
    blobController.dispose();
  }

  Future<void> _showBlobSheet({
    required String title,
    required String blob,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final spacing = context.appSpacing;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionHeader(title: title),
                SizedBox(height: spacing.md),
                AppSurfaceCard(
                  child: SelectableText(
                    blob,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout({required bool forgetDevice}) async {
    if (forgetDevice) {
      await widget.sessionController.logoutAndForgetDevice();
    } else {
      await widget.sessionController.logout();
    }
  }

  void _showMessage(String message, {required AppStatusTone tone}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: switch (tone) {
          AppStatusTone.success => context.appColors.success,
          AppStatusTone.warning => context.appColors.warning,
          AppStatusTone.danger => context.appColors.danger,
          AppStatusTone.info => context.appColors.info,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = context.appSpacing;
    final sessionUser = widget.sessionController.sessionUser!;
    final chatState = _controller.chatState;
    final contactsState = _controller.contactsState;
    final settingsState = _controller.settingsState;
    final tabs = [
      _TabMeta(
        label: context.antiQText(uz: 'Chatlar', en: 'Chats'),
        icon: HugeIcons.strokeRoundedChat,
        title:
            settingsState.currentWorkspace?.name ??
            context.antiQText(uz: 'Chatlar', en: 'Chats'),
      ),
      _TabMeta(
        label: context.antiQText(uz: 'Kontaktlar', en: 'Contacts'),
        icon: HugeIcons.strokeRoundedContactBook,
        title: context.antiQText(uz: 'Kontaktlar', en: 'Contacts'),
      ),
      _TabMeta(
        label: context.antiQText(uz: 'Sozlamalar', en: 'Settings'),
        icon: HugeIcons.strokeRoundedSettings02,
        title: context.antiQText(uz: 'Sozlamalar', en: 'Settings'),
      ),
      _TabMeta(
        label: context.antiQText(uz: 'Profil', en: 'Profile'),
        icon: HugeIcons.strokeRoundedUserCircle,
        title: context.antiQText(uz: 'Profil', en: 'Profile'),
      ),
    ];

    return AppScaffold(
      scaffoldKey: _scaffoldKey,
      drawer: _buildNavigationDrawer(settingsState),
      appBar: AppBar(
        toolbarHeight: 56,
        leadingWidth: 52,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: _PremiumIconButton(
            tooltip: context.antiQText(uz: 'Menyu', en: 'Menu'),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: Icons.menu_rounded,
          ),
        ),
        title: Text(
          tabs[_selectedTabIndex].title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AppAvatar(
              label: sessionUser.displayName,
              imageUrl: sessionUser.avatarUrl,
              radius: 17,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_controller.isLoading)
              const LinearProgressIndicator(minHeight: 2),
            if (_controller.error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  spacing.md,
                  spacing.lg,
                  0,
                ),
                child: AppStatusBanner(
                  message: _controller.error!,
                  tone: AppStatusTone.danger,
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _selectedTabIndex,
                children: [
                  RefreshIndicator(
                    onRefresh: _refresh,
                    child: _buildChatsTab(chatState),
                  ),
                  RefreshIndicator(
                    onRefresh: _refresh,
                    child: _buildContactsTab(contactsState),
                  ),
                  RefreshIndicator(
                    onRefresh: _refresh,
                    child: _buildSettingsOverview(settingsState),
                  ),
                  _buildAccountTab(settingsState),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(
          spacing.md,
          spacing.xs,
          spacing.md,
          spacing.sm,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.appColors.surface.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(context.appRadii.xl),
            border: Border.all(
              color: context.appColors.border.withValues(alpha: 0.72),
            ),
            boxShadow: context.appShadows.floating,
          ),
          child: _PremiumBottomNavigation(
            tabs: tabs,
            selectedIndex: _selectedTabIndex,
            onSelected: (index) => setState(() => _selectedTabIndex = index),
          ),
        ),
      ),
    );
  }

  Widget _buildChatsTab(ChatListViewState state) {
    final spacing = context.appSpacing;
    final items = state.items;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.xs,
        spacing.md,
        spacing.md,
      ),
      children: [
        if (_selectedConversationIds.isNotEmpty) ...[
          AppSurfaceCard(
            backgroundColor: context.appColors.primarySoft,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Tanlovni bekor qilish',
                  onPressed: () => setState(_selectedConversationIds.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
                Expanded(
                  child: Text(
                    '${_selectedConversationIds.length} ta tanlandi',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Tanlanganlarni arxivlash',
                  onPressed: _archiveSelectedConversations,
                  icon: const Icon(Icons.archive_outlined),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.sm),
        ],
        _buildCompactChatToolbar(state.preferences.selectedFilter),
        SizedBox(height: spacing.sm),
        if (_controller.isLoading && items.isEmpty)
          ..._buildChatSkeleton()
        else if (items.isEmpty)
          _buildEmptyCard(
            _emptyMessageForChatState(state.preferences.selectedFilter),
          )
        else
          for (final item in items)
            Dismissible(
              key: ValueKey('conversation-${item.conversation.id}'),
              direction: DismissDirection.horizontal,
              background: _swipeActionBackground(
                alignment: Alignment.centerLeft,
                color: context.appColors.primary,
                icon: Icons.mark_chat_read_outlined,
                label: 'O‘qilmagan',
              ),
              secondaryBackground: _swipeActionBackground(
                alignment: Alignment.centerRight,
                color: context.appColors.warning,
                icon: item.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                label: item.isArchived ? 'Qaytarish' : 'Arxivlash',
              ),
              confirmDismiss: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  await _controller.toggleManualUnread(item.conversation.id);
                } else {
                  await _controller.toggleArchived(item.conversation.id);
                }
                return false;
              },
              child: _ConversationListRow(
                item: item,
                selected: _selectedConversationIds.contains(
                  item.conversation.id,
                ),
                onTap: () => _selectedConversationIds.isNotEmpty
                    ? _toggleConversationSelection(item.conversation.id)
                    : _openConversationItem(item),
                onAvatarLongPress: () =>
                    _toggleConversationSelection(item.conversation.id),
                onLongPress: () => _selectedConversationIds.isNotEmpty
                    ? _toggleConversationSelection(item.conversation.id)
                    : _showConversationActions(item),
                relativeTime: _formatRelativeTime(item.updatedAt),
              ),
            ),
      ],
    );
  }

  Widget _buildCompactChatToolbar(ChatListFilter selectedFilter) {
    final spacing = context.appSpacing;
    return Row(
      children: [
        Expanded(
          child: AppSearchField(
            controller: _chatSearchController,
            hintText: context.antiQText(uz: 'Qidirish', en: 'Search'),
            compact: true,
            onChanged: _controller.setChatSearchQuery,
          ),
        ),
        SizedBox(width: spacing.xs),
        PopupMenuButton<ChatListFilter>(
          tooltip: context.antiQText(uz: 'Chat filtri', en: 'Chat filter'),
          initialValue: selectedFilter,
          onSelected: _controller.setChatFilter,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: ChatListFilter.all,
              child: Text(context.antiQText(uz: 'Barchasi', en: 'All')),
            ),
            PopupMenuItem(
              value: ChatListFilter.unread,
              child: Text(context.antiQText(uz: 'O‘qilmagan', en: 'Unread')),
            ),
            PopupMenuItem(
              value: ChatListFilter.pinned,
              child: Text(context.antiQText(uz: 'Mahkamlangan', en: 'Pinned')),
            ),
            PopupMenuItem(
              value: ChatListFilter.archived,
              child: Text(context.antiQText(uz: 'Arxiv', en: 'Archived')),
            ),
          ],
          child: Container(
            height: 42,
            padding: EdgeInsets.symmetric(horizontal: spacing.sm),
            decoration: BoxDecoration(
              color: selectedFilter == ChatListFilter.all
                  ? context.appColors.surfaceMuted
                  : context.appColors.primarySoft,
              borderRadius: BorderRadius.circular(context.appRadii.md),
              border: Border.all(
                color: selectedFilter == ChatListFilter.all
                    ? context.appColors.border.withValues(alpha: 0.58)
                    : context.appColors.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: selectedFilter == ChatListFilter.all
                      ? context.appColors.textMuted
                      : context.appColors.primary,
                ),
                if (selectedFilter != ChatListFilter.all) ...[
                  SizedBox(width: spacing.xs),
                  Text(
                    _chatFilterShortLabel(selectedFilter),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.appColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _chatFilterShortLabel(ChatListFilter filter) => switch (filter) {
    ChatListFilter.all => context.antiQText(uz: 'Barchasi', en: 'All'),
    ChatListFilter.unread => context.antiQText(uz: 'Yangi', en: 'Unread'),
    ChatListFilter.pinned => context.antiQText(uz: 'Muhim', en: 'Pinned'),
    ChatListFilter.archived => context.antiQText(uz: 'Arxiv', en: 'Archived'),
  };

  Widget _swipeActionBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      alignment: alignment,
      margin: EdgeInsets.symmetric(vertical: context.appSpacing.xs),
      padding: EdgeInsets.symmetric(horizontal: context.appSpacing.lg),
      color: color.withValues(alpha: 0.14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          SizedBox(width: context.appSpacing.xs),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  void _toggleConversationSelection(int conversationId) {
    setState(() {
      if (!_selectedConversationIds.add(conversationId)) {
        _selectedConversationIds.remove(conversationId);
      }
    });
  }

  Future<void> _archiveSelectedConversations() async {
    final ids = List<int>.of(_selectedConversationIds);
    for (final id in ids) {
      await _controller.toggleArchived(id);
    }
    if (mounted) setState(_selectedConversationIds.clear);
  }

  Widget _buildContactsTab(ContactsViewState state) {
    final spacing = context.appSpacing;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.sm,
        spacing.lg,
        spacing.lg,
      ),
      children: [
        AppSearchField(
          controller: _contactsSearchController,
          hintText: context.antiQText(
            uz: 'Kontaktlarni qidiring',
            en: 'Search contacts',
          ),
          onChanged: _controller.setContactsSearchQuery,
        ),
        SizedBox(height: spacing.md),
        _buildContactsFilterSelector(state.selectedFilter),
        SizedBox(height: spacing.lg),
        if (_controller.isLoading && state.sections.isEmpty)
          ..._buildContactSkeleton()
        else if (state.sections.isEmpty)
          _buildEmptyCard(
            context.antiQText(
              uz: 'Bu filtr bo‘yicha kontakt topilmadi.',
              en: 'No contacts match this filter.',
            ),
          )
        else
          for (final section in state.sections) ...[
            AppSectionHeader(title: section.label),
            SizedBox(height: spacing.xs),
            for (final item in section.items)
              _ContactListRow(
                item: item,
                onTap: () => _showContactDetails(item),
              ),
            SizedBox(height: spacing.md),
          ],
      ],
    );
  }

  // Legacy all-in-one layout kept temporarily as a migration reference.
  // ignore: unused_element
  Widget _buildSettingsTab(SettingsViewState state) {
    final spacing = context.appSpacing;
    final theme = Theme.of(context);
    final sessionUser = state.sessionUser;
    return ListView(
      padding: EdgeInsets.all(spacing.lg),
      children: [
        AppSurfaceCard(
          backgroundColor: context.appColors.primarySoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppBrandMark(size: 48),
              SizedBox(height: spacing.lg),
              Text(
                'Profil va ish maydoni',
                style: theme.textTheme.headlineSmall,
              ),
              SizedBox(height: spacing.md),
              _buildInfoRow('Ko‘rinadigan ism', sessionUser.displayName),
              _buildInfoRow('Foydalanuvchi nomi', sessionUser.username),
              _buildInfoRow(
                'Ish maydoni',
                state.currentWorkspace?.name ?? 'Mavjud emas',
              ),
              _buildInfoRow(
                'Ish maydoni ID',
                '${sessionUser.activeWorkspaceId}',
              ),
              _buildInfoRow('Qurilma ID', sessionUser.deviceId),
              _buildInfoRow('Ko‘rinish', state.appSkinId),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        const AppSectionHeader(
          title: 'Xavfsizlik markazi',
          subtitle: 'Ishonch, qurilma tayyorligi va eski xabarlar holati.',
        ),
        SizedBox(height: spacing.sm),
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: spacing.sm,
                runSpacing: spacing.sm,
                children: [
                  AppBadge(
                    label: '${state.security.verifiedPeersCount} tasdiqlangan',
                    tone: AppStatusTone.success,
                  ),
                  AppBadge(
                    label:
                        '${state.security.needsAttentionCount} e’tibor talab qiladi',
                    tone: AppStatusTone.warning,
                  ),
                  AppBadge(
                    label: '${state.security.notReadyCount} tayyor emas',
                    tone: AppStatusTone.danger,
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              AppStatusBanner(
                message: state.security.hasHistoricalDecryptCapability
                    ? 'Eski xabarlarni ochish tayyor. ${state.security.availableHistoricalKeysets} ta kalitlar to‘plami mavjud.'
                    : 'Eski xabarlarni ochish cheklangan. Zaxirani tiklash tavsiya etiladi.',
                tone: state.security.hasHistoricalDecryptCapability
                    ? AppStatusTone.success
                    : AppStatusTone.warning,
              ),
              SizedBox(height: spacing.md),
              AppStatusBanner(
                message: state.security.isCurrentDeviceReady
                    ? 'Joriy qurilma PQC uchun tayyor.'
                    : 'Joriy qurilma hali to‘liq tayyor emas.',
                tone: state.security.isCurrentDeviceReady
                    ? AppStatusTone.success
                    : AppStatusTone.warning,
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        const AppSectionHeader(
          title: 'Zaxira va tiklash',
          subtitle: 'Akkauntga bog‘langan avtomatik shifrlangan tiklash.',
        ),
        SizedBox(height: spacing.sm),
        if (state.backup.statusMessage != null) ...[
          AppStatusBanner(
            message: state.backup.statusMessage!,
            tone: _statusTone(state.backup.statusTone),
          ),
          SizedBox(height: spacing.sm),
        ],
        AppSurfaceCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Korporativ tarixni tiklash'),
                subtitle: const Text(
                  'AWS KMS escrow manifestini faqat siz Restore history tugmasini bosganingizda import qilamiz.',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Tiklash so‘rovlari',
                      icon: const Icon(Icons.verified_user_outlined),
                      onPressed: _showPendingRecoveryApprovals,
                    ),
                    IconButton(
                      tooltip: 'Tarixni tiklash',
                      icon: const Icon(Icons.restore_rounded),
                      onPressed: () async {
                        try {
                          await _controller.restoreEnterpriseRecovery();
                        } catch (error) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        const AppSectionHeader(
          title: 'Qurilmalar va seanslar',
          subtitle: 'Joriy va ro‘yxatdan o‘tgan qurilmalar.',
        ),
        SizedBox(height: spacing.sm),
        if (state.currentDevice != null)
          AppSurfaceCard(
            backgroundColor: context.appColors.surfaceStrong,
            child: Row(
              children: [
                const AppAvatar(
                  label: 'D',
                  icon: Icons.shield_outlined,
                  radius: 20,
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.currentDevice!.deviceName.isEmpty
                            ? 'Joriy qurilma'
                            : state.currentDevice!.deviceName,
                        style: theme.textTheme.titleMedium,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        '${state.currentDevice!.platform.isEmpty ? 'noma’lum' : state.currentDevice!.platform} • ${state.currentDevice!.status}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                AppBadge(
                  label:
                      state.currentDevice!.hasUsableMlKemKey &&
                          state.currentDevice!.hasUsableMlDsaKey
                      ? 'PQC tayyor'
                      : 'Sozlash kerak',
                  tone:
                      state.currentDevice!.hasUsableMlKemKey &&
                          state.currentDevice!.hasUsableMlDsaKey
                      ? AppStatusTone.success
                      : AppStatusTone.warning,
                ),
              ],
            ),
          )
        else
          _buildEmptyCard('Joriy qurilma ma’lumoti mavjud emas.'),
        SizedBox(height: spacing.sm),
        for (final device in state.devices)
          Padding(
            padding: EdgeInsets.only(bottom: spacing.sm),
            child: AppSurfaceCard(
              child: Row(
                children: [
                  const AppAvatar(
                    label: 'D',
                    icon: Icons.devices_outlined,
                    radius: 18,
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.deviceName.isEmpty
                              ? device.deviceId
                              : device.deviceName,
                          style: theme.textTheme.titleMedium,
                        ),
                        SizedBox(height: spacing.xs),
                        Text(
                          '${device.platform.isEmpty ? 'noma’lum' : device.platform} • ${device.status} • barmoq izi ${device.profileFingerprint.isEmpty ? 'yo‘q' : 'mavjud'}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.appColors.textMuted,
                          ),
                        ),
                        if (device.lastSeenAt != null) ...[
                          SizedBox(height: spacing.xs),
                          Text(
                            'Oxirgi faollik: ${_formatRelativeTime(device.lastSeenAt!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context.appColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AppBadge(
                    label: device.hasUsableMlKemKey && device.hasUsableMlDsaKey
                        ? 'Tayyor'
                        : 'Tayyor emas',
                    tone: device.hasUsableMlKemKey && device.hasUsableMlDsaKey
                        ? AppStatusTone.success
                        : AppStatusTone.warning,
                  ),
                ],
              ),
            ),
          ),
        SizedBox(height: spacing.lg),
        const AppSectionHeader(
          title: 'Afzalliklar',
          subtitle: 'Chatlar oynasi uchun mahalliy sozlamalar.',
        ),
        SizedBox(height: spacing.sm),
        AppSurfaceCard(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: widget.themeController.themeMode == ThemeMode.dark,
                title: const Text('Qorong‘i rejim'),
                subtitle: const Text(
                  'Light va dark ko‘rinish o‘rtasida almashish.',
                ),
                onChanged: (value) {
                  widget.themeController.setThemeMode(
                    value ? ThemeMode.dark : ThemeMode.light,
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.appPreferences.showArchivedByDefault,
                title: const Text('Arxivni asosiy ro‘yxatda ko‘rsatish'),
                subtitle: const Text(
                  'Archived chats “All” ichida ham ko‘rinsin.',
                ),
                onChanged: (value) {
                  _controller.updateAppPreferences(
                    state.appPreferences.copyWith(showArchivedByDefault: value),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.appPreferences.keepDrafts,
                title: const Text('Qoralamalarni saqlash'),
                subtitle: const Text('Composer draftlari avtomatik saqlansin.'),
                onChanged: (value) {
                  _controller.updateAppPreferences(
                    state.appPreferences.copyWith(keepDrafts: value),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.appPreferences.preferManualRefreshHints,
                title: const Text(
                  'Qo‘lda yangilash ko‘rsatmalarini afzal ko‘rish',
                ),
                subtitle: const Text(
                  'Auto refresh o‘rniga ko‘proq manual affordance.',
                ),
                onChanged: (value) {
                  _controller.updateAppPreferences(
                    state.appPreferences.copyWith(
                      preferManualRefreshHints: value,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        const AppSectionHeader(
          title: 'Dastur va yordam',
          subtitle: 'Versiya ma’lumoti va yordam aloqasi.',
        ),
        SizedBox(height: spacing.sm),
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Versiya', state.appVersion),
              _buildInfoRow('Yordam', state.supportEmail),
              _buildInfoRow('API', state.apiBaseUrl),
            ],
          ),
        ),
        SizedBox(height: spacing.lg),
        Row(
          children: [
            Expanded(
              child: AppSecondaryButton(
                onPressed: () => _logout(forgetDevice: false),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Chiqish'),
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: AppPrimaryButton(
                onPressed: () => _logout(forgetDevice: true),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Qurilmani unutish'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNavigationDrawer(SettingsViewState state) {
    final session = state.sessionUser;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: context.appColors.primarySoft),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAvatar(
                    label: session.displayName,
                    imageUrl: session.avatarUrl,
                    radius: 28,
                  ),
                  const Spacer(),
                  Text(
                    session.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    session.username,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (state.currentUser?.roleLabel.isNotEmpty == true)
                    Text(
                      state.currentUser!.roleLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.appColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedChat,
                size: 21,
              ),
              title: Text(context.antiQText(uz: 'Chatlar', en: 'Chats')),
              onTap: () {
                _scaffoldKey.currentState?.closeDrawer();
                setState(() => _selectedTabIndex = 0);
              },
            ),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedContactBook,
                size: 21,
              ),
              title: Text(context.antiQText(uz: 'Kontaktlar', en: 'Contacts')),
              onTap: () {
                _scaffoldKey.currentState?.closeDrawer();
                setState(() => _selectedTabIndex = 1);
              },
            ),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedSettings02,
                size: 21,
              ),
              title: Text(context.antiQText(uz: 'Sozlamalar', en: 'Settings')),
              onTap: () {
                _scaffoldKey.currentState?.closeDrawer();
                setState(() => _selectedTabIndex = 2);
              },
            ),
            const Divider(),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedUserCircle,
                size: 21,
              ),
              title: Text(context.antiQText(uz: 'Profil', en: 'Profile')),
              onTap: () {
                _scaffoldKey.currentState?.closeDrawer();
                setState(() => _selectedTabIndex = 3);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: Text(context.antiQText(uz: 'Chiqish', en: 'Log out')),
              onTap: () async {
                _scaffoldKey.currentState?.closeDrawer();
                await _logout(forgetDevice: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountTab(SettingsViewState state) {
    final spacing = context.appSpacing;
    final session = state.sessionUser;
    return ListView(
      padding: EdgeInsets.all(spacing.md),
      children: [
        AppSurfaceCard(
          backgroundColor: context.appColors.primarySoft,
          child: Column(
            children: [
              AppAvatar(
                label: session.displayName,
                imageUrl: session.avatarUrl,
                radius: 36,
              ),
              SizedBox(height: spacing.md),
              Text(
                session.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                session.username,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textMuted,
                ),
              ),
              if (state.currentUser?.roleLabel.isNotEmpty == true) ...[
                SizedBox(height: spacing.xs),
                AppBadge(
                  label: state.currentUser!.roleLabel,
                  tone: AppStatusTone.info,
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: spacing.md),
        AppSurfaceCard(
          child: Column(
            children: [
              _buildInfoRow(
                'Ish maydoni',
                state.currentWorkspace?.name ?? 'Mavjud emas',
              ),
              _buildInfoRow('Qurilma', session.deviceId),
            ],
          ),
        ),
        SizedBox(height: spacing.md),
        AppPrimaryButton(
          onPressed: _showEditProfile,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Profilni tahrirlash'),
        ),
      ],
    );
  }

  Widget _buildSettingsOverview(SettingsViewState state) {
    final spacing = context.appSpacing;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.xs,
        spacing.md,
        spacing.md,
      ),
      children: [
        AppSectionHeader(
          title: context.antiQText(uz: 'Sozlamalar', en: 'Settings'),
          subtitle: context.antiQText(
            uz: 'Kerakli bo‘limni tanlang.',
            en: 'Choose a section.',
          ),
        ),
        SizedBox(height: spacing.xs),
        _settingsSection(
          context.antiQText(uz: 'Akkaunt', en: 'Account'),
          context.antiQText(
            uz: 'Profil, ish maydoni va seans',
            en: 'Profile, workspace and session',
          ),
          Icons.person_outline_rounded,
          _buildAccountSettings,
        ),
        _settingsSection(
          context.antiQText(uz: 'Xavfsizlik', en: 'Security'),
          context.antiQText(
            uz: 'Ishonch, kalitlar va shifrni ochish holati',
            en: 'Trust, keys and decryption health',
          ),
          Icons.shield_outlined,
          _buildSecuritySettings,
        ),
        _settingsSection(
          context.antiQText(uz: 'Qurilmalar', en: 'Devices'),
          context.antiQText(
            uz: 'Ro‘yxatdagi qurilmalar va bekor qilish',
            en: 'Registered devices and revoke',
          ),
          Icons.devices_outlined,
          _buildDevicesSettings,
        ),
        _settingsSection(
          context.antiQText(uz: 'Zaxira va tiklash', en: 'Backup & Recovery'),
          context.antiQText(
            uz: 'Tiklash va ko‘chma shifrlangan zaxiralar',
            en: 'Restore and portable encrypted backups',
          ),
          Icons.backup_outlined,
          _buildBackupSettings,
        ),
        _settingsSection(
          context.antiQText(
            uz: 'Bildirishnomalar va maxfiylik',
            en: 'Notifications & Privacy',
          ),
          context.antiQText(
            uz: 'Ogohlantirishlar, yozish va faollik',
            en: 'Alerts, typing and presence',
          ),
          Icons.notifications_outlined,
          _buildNotificationsSettings,
        ),
        _settingsSection(
          context.antiQText(
            uz: 'Ko‘rinish va chatlar',
            en: 'Appearance & Chats',
          ),
          context.antiQText(
            uz: 'Mavzu, qoralamalar va chatlar joylashuvi',
            en: 'Theme, drafts and inbox layout',
          ),
          Icons.palette_outlined,
          _buildAppearanceSettings,
        ),
        _settingsSection(
          context.antiQText(uz: 'Dastur va yordam', en: 'About & Support'),
          context.antiQText(
            uz: 'Versiya va yordam tafsilotlari',
            en: 'Version and support details',
          ),
          Icons.info_outline_rounded,
          _buildAboutSettings,
        ),
      ],
    );
  }

  Widget _settingsSection(
    String title,
    String subtitle,
    IconData icon,
    Widget Function(SettingsViewState) builder,
  ) {
    final spacing = context.appSpacing;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(context.appRadii.md),
        onTap: () => Navigator.of(context).push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 220),
            reverseTransitionDuration: const Duration(milliseconds: 180),
            pageBuilder: (_, animation, _) {
              final curve = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );
              return FadeTransition(
                opacity: curve,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.015, 0.02),
                    end: Offset.zero,
                  ).animate(curve),
                  child: _SettingsPage(
                    title: title,
                    child: ListenableBuilder(
                      listenable: _controller,
                      builder: (_, _) => builder(_controller.settingsState),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: context.appColors.border.withValues(alpha: 0.65),
              ),
            ),
          ),
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            contentPadding: EdgeInsets.symmetric(horizontal: spacing.xs),
            leading: Icon(icon, color: context.appColors.primary),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ),
    );
  }

  Widget _settingsList(List<Widget> children) => ListView(
    padding: EdgeInsets.all(context.appSpacing.md),
    children: children,
  );

  Widget _buildAccountSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    final session = state.sessionUser;
    return _settingsList([
      AppSurfaceCard(
        backgroundColor: context.appColors.primarySoft,
        child: Column(
          children: [
            AppAvatar(
              label: session.displayName,
              imageUrl: session.avatarUrl,
              radius: 38,
            ),
            SizedBox(height: spacing.md),
            Text(
              session.displayName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              session.username,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
            SizedBox(height: spacing.sm),
            TextButton.icon(
              onPressed: _showEditProfile,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Profilni tahrirlash'),
            ),
          ],
        ),
      ),
      SizedBox(height: spacing.lg),
      const AppSectionHeader(title: 'Ish maydoni'),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          children: [
            _buildInfoRow(
              'Joriy',
              state.currentWorkspace?.name ?? 'Mavjud emas',
            ),
            for (final organization in session.organizations)
              for (final workspace in organization.workspaces)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    workspace.id == session.activeWorkspaceId
                        ? Icons.check_circle_rounded
                        : Icons.apartment_outlined,
                  ),
                  title: Text(workspace.name),
                  subtitle: Text(organization.name),
                  onTap: workspace.id == session.activeWorkspaceId
                      ? null
                      : () => _switchWorkspace(workspace.id),
                ),
          ],
        ),
      ),
      SizedBox(height: spacing.lg),
      AppSurfaceCard(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Akkauntdan chiqish'),
              subtitle: const Text('Bu qurilma ro‘yxatda qoladi.'),
              onTap: () => _logout(forgetDevice: false),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: context.appColors.danger,
              ),
              title: const Text('Bu qurilmani unutish'),
              subtitle: const Text(
                'Mahalliy seans va mahalliy tarix o‘chiriladi.',
              ),
              onTap: () => _logout(forgetDevice: true),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildSecuritySettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Xavfsizlik markazi',
        subtitle: 'Ishonch va eski xabarlarni ochish tayyorligi.',
      ),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: spacing.sm,
              runSpacing: spacing.sm,
              children: [
                AppBadge(
                  label: '${state.security.verifiedPeersCount} tasdiqlangan',
                  tone: AppStatusTone.success,
                ),
                AppBadge(
                  label:
                      '${state.security.needsAttentionCount} e’tibor talab qiladi',
                  tone: AppStatusTone.warning,
                ),
                AppBadge(
                  label: '${state.security.notReadyCount} tayyor emas',
                  tone: AppStatusTone.danger,
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            AppStatusBanner(
              message: state.security.hasHistoricalDecryptCapability
                  ? 'Eski xabarlarni ochish tayyor. ${state.security.availableHistoricalKeysets} ta kalitlar to‘plami mavjud.'
                  : 'Eski xabarlarni ochish cheklangan. Eski xabarlar uchun zaxirani tiklang.',
              tone: state.security.hasHistoricalDecryptCapability
                  ? AppStatusTone.success
                  : AppStatusTone.warning,
            ),
            SizedBox(height: spacing.sm),
            AppStatusBanner(
              message: state.security.isCurrentDeviceReady
                  ? 'Bu qurilma xavfsiz xabar almashishga tayyor.'
                  : 'Bu qurilmada kalitlarni sozlash kerak.',
              tone: state.security.isCurrentDeviceReady
                  ? AppStatusTone.success
                  : AppStatusTone.warning,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildDevicesSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Qurilmalar va seanslar',
        subtitle: 'Faqat o‘zingiz tanimaydigan qurilmalarni bekor qiling.',
      ),
      SizedBox(height: spacing.sm),
      for (final device in state.devices)
        Padding(
          padding: EdgeInsets.only(bottom: spacing.sm),
          child: AppSurfaceCard(
            child: ListTile(
              leading: Icon(
                device.deviceId == state.sessionUser.deviceId
                    ? Icons.phone_android_rounded
                    : Icons.devices_outlined,
              ),
              title: Text(
                device.deviceName.isEmpty ? device.deviceId : device.deviceName,
              ),
              subtitle: Text(
                '${device.platform.isEmpty ? 'Noma’lum platforma' : device.platform} • ${device.status}',
              ),
              trailing: device.deviceId == state.sessionUser.deviceId
                  ? const AppBadge(
                      label: 'Bu qurilma',
                      tone: AppStatusTone.info,
                    )
                  : IconButton(
                      tooltip: 'Qurilmani bekor qilish',
                      icon: Icon(
                        Icons.remove_circle_outline_rounded,
                        color: context.appColors.danger,
                      ),
                      onPressed: () => _confirmDeviceRevoke(device),
                    ),
            ),
          ),
        ),
      if (state.devices.isEmpty)
        _buildEmptyCard('Ro‘yxatdan o‘tgan qurilma topilmadi.'),
    ]);
  }

  Widget _buildBackupSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Zaxira va tiklash',
        subtitle:
            'Qayta o‘rnatish yoki qurilma almashtirishdan keyin tarixni tiklash.',
      ),
      SizedBox(height: spacing.sm),
      if (state.backup.statusMessage != null)
        AppStatusBanner(
          message: state.backup.statusMessage!,
          tone: _statusTone(state.backup.statusTone),
        ),
      AppSurfaceCard(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Shifrlangan tarixni tiklash'),
              subtitle: const Text(
                'Tasdiqlangandan keyin akkaunt tiklash ma’lumotini import qiling.',
              ),
              onTap: _restoreEnterpriseRecovery,
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Tiklash ruxsatlari'),
              subtitle: const Text(
                'Boshqa qurilmalaringiz so‘rovlarini ko‘ring.',
              ),
              onTap: _showPendingRecoveryApprovals,
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Shifrlangan zaxirani eksport qilish'),
              onTap: _showExportBackupSheet,
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Shifrlangan zaxirani import qilish'),
              onTap: _showImportBackupSheet,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildNotificationsSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Bildirishnomalar',
        subtitle: 'Bu sozlamalar akkauntingiz bilan sinxronlanadi.',
      ),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notificationsEnabled,
              title: const Text('Bildirishnomalar'),
              onChanged: (value) =>
                  _setAccountBool('notifications_enabled', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notificationPreviewsEnabled,
              title: const Text('Bildirishnoma matni'),
              subtitle: const Text('Ogohlantirishda xabar matnini ko‘rsatish.'),
              onChanged: (value) =>
                  _setAccountBool('notification_previews', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _readReceiptsEnabled,
              title: const Text('O‘qilganlik belgisi'),
              onChanged: (value) =>
                  _setAccountBool('read_receipts_enabled', value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _typingIndicatorsEnabled,
              title: const Text('Yozayotganlik belgisi'),
              onChanged: (value) =>
                  _setAccountBool('typing_indicators_enabled', value),
            ),
            _visibilitySetting(
              'Oxirgi faollik ko‘rinishi',
              _lastSeenVisibility,
              _setLastSeenVisibility,
            ),
            _visibilitySetting(
              'Onlayn holati ko‘rinishi',
              _onlineVisibility,
              _setOnlineVisibility,
            ),
          ],
        ),
      ),
      SizedBox(height: spacing.lg),
      const AppSurfaceCard(
        child: ListTile(
          leading: Icon(Icons.lock_outline_rounded),
          title: Text('Xabar mazmuni'),
          subtitle: Text(
            'Xabar mazmuni boshidan oxirigacha shifrlanadi va server uni o‘qiy olmaydi.',
          ),
        ),
      ),
    ]);
  }

  Widget _visibilitySetting(
    String title,
    String value,
    ValueChanged<String> onChanged,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: 'everyone', child: Text('Hamma')),
          DropdownMenuItem(value: 'contacts', child: Text('Kontaktlar')),
          DropdownMenuItem(value: 'nobody', child: Text('Hech kim')),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    ),
  );

  Widget _buildAppearanceSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      AppSectionHeader(
        title: context.antiQText(
          uz: 'Ko‘rinish va chatlar',
          en: 'Appearance & Chats',
        ),
        subtitle: context.antiQText(
          uz: 'Ko‘rinish va xabar yozishning mahalliy sozlamalari.',
          en: 'Local display and composer preferences.',
        ),
      ),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language_rounded),
              title: Text(
                context.antiQText(uz: 'Dastur tili', en: 'App language'),
              ),
              subtitle: Text(
                context.antiQText(
                  uz: 'Interfeys tilini tanlang.',
                  en: 'Choose the interface language.',
                ),
              ),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<AppLanguagePreference>(
                  value: widget.themeController.languagePreference,
                  items: const [
                    DropdownMenuItem(
                      value: AppLanguagePreference.uzbek,
                      child: Text('O‘zbekcha'),
                    ),
                    DropdownMenuItem(
                      value: AppLanguagePreference.english,
                      child: Text('English'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.themeController.setLanguage(value);
                    }
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.themeController.themeMode == ThemeMode.dark,
              title: Text(
                context.antiQText(uz: 'Qorong‘i rejim', en: 'Dark mode'),
              ),
              onChanged: (value) => widget.themeController.setThemeMode(
                value ? ThemeMode.dark : ThemeMode.light,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.appPreferences.showArchivedByDefault,
              title: Text(
                context.antiQText(
                  uz: 'Arxivlangan chatlarni ko‘rsatish',
                  en: 'Show archived chats',
                ),
              ),
              onChanged: (value) => _controller.updateAppPreferences(
                state.appPreferences.copyWith(showArchivedByDefault: value),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.appPreferences.keepDrafts,
              title: Text(
                context.antiQText(
                  uz: 'Qoralamalarni saqlash',
                  en: 'Keep drafts',
                ),
              ),
              onChanged: (value) => _controller.updateAppPreferences(
                state.appPreferences.copyWith(keepDrafts: value),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildAboutSettings(SettingsViewState state) => _settingsList([
    const AppSectionHeader(title: 'Dastur va yordam'),
    SizedBox(height: context.appSpacing.sm),
    AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Versiya', state.appVersion),
          _buildInfoRow('Yordam', state.supportEmail),
          _buildInfoRow('API', state.apiBaseUrl),
        ],
      ),
    ),
  ]);

  Future<void> _restoreEnterpriseRecovery() async {
    try {
      await _controller.restoreEnterpriseRecovery();
    } catch (error) {
      if (mounted) _showMessage(error.toString(), tone: AppStatusTone.danger);
    }
  }

  void _setAccountBool(String key, bool value) {
    setState(() {
      switch (key) {
        case 'notifications_enabled':
          _notificationsEnabled = value;
        case 'notification_previews':
          _notificationPreviewsEnabled = value;
        case 'read_receipts_enabled':
          _readReceiptsEnabled = value;
        case 'typing_indicators_enabled':
          _typingIndicatorsEnabled = value;
      }
    });
    _controller.updateAccountSettings({key: value});
  }

  void _setLastSeenVisibility(String value) {
    setState(() => _lastSeenVisibility = value);
    _controller.updateAccountSettings({'last_seen_visibility': value});
  }

  void _setOnlineVisibility(String value) {
    setState(() => _onlineVisibility = value);
    _controller.updateAccountSettings({'online_visibility': value});
  }

  Future<void> _confirmDeviceRevoke(AppUserDevice device) async {
    final label = device.deviceName.isEmpty
        ? device.deviceId
        : device.deviceName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Qurilma bekor qilinsinmi?'),
        content: Text('$label endi bu akkauntga kira olmaydi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bekor qilishni tasdiqlash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _controller.revokeDevice(device.deviceId);
      if (mounted) {
        _showMessage('Qurilma bekor qilindi.', tone: AppStatusTone.success);
      }
    } catch (error) {
      if (mounted) _showMessage(error.toString(), tone: AppStatusTone.danger);
    }
  }

  Widget _buildContactsFilterSelector(ContactsTrustFilter filter) {
    return _FilterStrip<ContactsTrustFilter>(
      selected: filter,
      options: const [
        _FilterOption(value: ContactsTrustFilter.all, label: 'Barchasi'),
        _FilterOption(
          value: ContactsTrustFilter.verified,
          label: 'Tasdiqlangan',
        ),
        _FilterOption(
          value: ContactsTrustFilter.needsAttention,
          label: 'E’tibor kerak',
        ),
        _FilterOption(
          value: ContactsTrustFilter.notReady,
          label: 'Tayyor emas',
        ),
      ],
      onSelected: _controller.setContactsFilter,
    );
  }

  List<Widget> _buildChatSkeleton() {
    final spacing = context.appSpacing;
    return List<Widget>.generate(
      4,
      (index) => Padding(
        padding: EdgeInsets.only(bottom: spacing.sm),
        child: AppSurfaceCard(
          child: Row(
            children: [
              const AppAvatar(label: 'S'),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSkeletonBlock(height: 16, width: 160),
                    SizedBox(height: spacing.sm),
                    const AppSkeletonBlock(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContactSkeleton() {
    final spacing = context.appSpacing;
    return List<Widget>.generate(
      4,
      (index) => Padding(
        padding: EdgeInsets.only(bottom: spacing.sm),
        child: AppSurfaceCard(
          child: Row(
            children: [
              const AppAvatar(label: 'S'),
              SizedBox(width: spacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonBlock(height: 16, width: 180),
                    SizedBox(height: 10),
                    AppSkeletonBlock(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final spacing = context.appSpacing;
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          AppAvatar(label: title, icon: icon, radius: 18),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: spacing.xs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.appColors.textMuted),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final spacing = context.appSpacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String text) {
    return AppEmptyState(message: text);
  }

  String _emptyMessageForChatState(ChatListFilter filter) {
    switch (filter) {
      case ChatListFilter.unread:
        return context.antiQText(
          uz: 'O‘qilmagan chat topilmadi.',
          en: 'No unread chats.',
        );
      case ChatListFilter.pinned:
        return context.antiQText(
          uz: 'Mahkamlangan chatlar hali yo‘q.',
          en: 'No pinned chats yet.',
        );
      case ChatListFilter.archived:
        return context.antiQText(
          uz: 'Arxivlangan chatlar hali yo‘q.',
          en: 'No archived chats.',
        );
      case ChatListFilter.all:
        return context.antiQText(
          uz: 'Hali chatlar yo‘q. Kontaktlar bo‘limidan suhbat boshlashingiz mumkin.',
          en: 'No chats yet. Start a conversation from Contacts.',
        );
    }
  }

  String _formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final local = time.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final dayDifference = today.difference(messageDay).inDays;
    if (dayDifference <= 0) {
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    if (dayDifference == 1) {
      return context.antiQText(uz: 'Kecha', en: 'Yesterday');
    }
    if (dayDifference < 7) {
      const weekdays = ['Du', 'Se', 'Cho', 'Pa', 'Ju', 'Sha', 'Ya'];
      return weekdays[local.weekday - 1];
    }
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
  }

  AppStatusTone _statusTone(UiStatusTone tone) {
    switch (tone) {
      case UiStatusTone.success:
        return AppStatusTone.success;
      case UiStatusTone.warning:
        return AppStatusTone.warning;
      case UiStatusTone.danger:
        return AppStatusTone.danger;
      case UiStatusTone.info:
        return AppStatusTone.info;
    }
  }
}

class _ConversationListRow extends StatelessWidget {
  const _ConversationListRow({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onAvatarLongPress,
    required this.relativeTime,
  });

  final ConversationListItemState item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAvatarLongPress;
  final String relativeTime;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final isAttention =
        item.trustBadge?.tone == UiStatusTone.warning ||
        item.trustBadge?.tone == UiStatusTone.danger;
    final preview = item.hasDraft
        ? '${context.antiQText(uz: 'Qoralama', en: 'Draft')}: ${item.draftPreview!.trim()}'
        : item.preview.isEmpty
        ? context.antiQText(uz: 'Suhbatni ochish', en: 'Open conversation')
        : item.preview;

    return AnimatedContainer(
      duration: context.appDurations.fast,
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: selected ? colors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(context.appRadii.md),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(context.appRadii.md),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              spacing.xs,
              spacing.sm,
              spacing.xs,
              spacing.sm,
            ),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: onAvatarLongPress,
                  child: AnimatedSwitcher(
                    duration: context.appDurations.fast,
                    child: selected
                        ? Container(
                            key: const ValueKey('selected'),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                            ),
                          )
                        : AppAvatar(
                            key: const ValueKey('avatar'),
                            label: item.title,
                            imageUrl: item.avatarUrl,
                            icon: item.conversation.isGroup
                                ? Icons.forum_outlined
                                : null,
                            radius: 22,
                          ),
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: item.isUnread
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                  ),
                                ),
                                if (item.isPinned) ...[
                                  SizedBox(width: spacing.xs),
                                  Icon(
                                    Icons.push_pin_rounded,
                                    size: 14,
                                    color: colors.textMuted,
                                  ),
                                ],
                                if (isAttention) ...[
                                  SizedBox(width: spacing.xs),
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 15,
                                    color: colors.warning,
                                  ),
                                ],
                                if (item.roleLabel.isNotEmpty &&
                                    !item.conversation.isGroup) ...[
                                  SizedBox(width: spacing.xs),
                                  Flexible(
                                    child: Text(
                                      '• ${item.roleLabel}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colors.textMuted,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(width: spacing.sm),
                          Text(
                            relativeTime,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: item.isUnread
                                      ? colors.primary
                                      : colors.textMuted,
                                  fontWeight: item.isUnread
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (item.deliveryState != null) ...[
                            Icon(
                              _deliveryIcon(item.deliveryState!),
                              size: 15,
                              color: _deliveryColor(
                                colors,
                                item.deliveryState!,
                              ),
                            ),
                            SizedBox(width: spacing.xs),
                          ],
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: item.hasDraft
                                        ? colors.primary
                                        : colors.textMuted,
                                    fontWeight: item.hasDraft
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                            ),
                          ),
                          if (item.isUnread) ...[
                            SizedBox(width: spacing.sm),
                            Container(
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                item.unreadCount > 0
                                    ? '${item.unreadCount}'
                                    : '',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _deliveryIcon(MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.pending:
        return Icons.schedule_rounded;
      case MessageDeliveryState.failedRetryable:
        return Icons.error_outline_rounded;
      case MessageDeliveryState.failedPermanent:
        return Icons.block_rounded;
      case MessageDeliveryState.sent:
        return Icons.done_all_rounded;
    }
  }

  Color _deliveryColor(AppColors colors, MessageDeliveryState state) {
    switch (state) {
      case MessageDeliveryState.pending:
        return colors.textMuted;
      case MessageDeliveryState.failedRetryable:
      case MessageDeliveryState.failedPermanent:
        return colors.danger;
      case MessageDeliveryState.sent:
        return colors.primary;
    }
  }
}

class _PremiumIconButton extends StatelessWidget {
  const _PremiumIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      style: IconButton.styleFrom(
        backgroundColor: context.appColors.surfaceMuted,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: BorderSide(
          color: context.appColors.border.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _PremiumBottomNavigation extends StatelessWidget {
  const _PremiumBottomNavigation({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_TabMeta> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index++)
            Expanded(
              child: Semantics(
                selected: selectedIndex == index,
                button: true,
                label: tabs[index].label,
                child: InkWell(
                  onTap: () => onSelected(index),
                  child: AnimatedContainer(
                    duration: context.appDurations.fast,
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selectedIndex == index
                          ? colors.primarySoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        context.appRadii.pill,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          duration: context.appDurations.fast,
                          scale: selectedIndex == index ? 1.06 : 1,
                          child: HugeIcon(
                            icon: tabs[index].icon,
                            size: 20,
                            strokeWidth: selectedIndex == index ? 2.1 : 1.7,
                            color: selectedIndex == index
                                ? colors.primary
                                : colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tabs[index].label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontSize: 10,
                                height: 1,
                                color: selectedIndex == index
                                    ? colors.primary
                                    : colors.textMuted,
                                fontWeight: selectedIndex == index
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContactListRow extends StatelessWidget {
  const _ContactListRow({required this.item, required this.onTap});

  final ContactListItemState item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final toneColor = switch (item.badge.tone) {
      UiStatusTone.success => colors.success,
      UiStatusTone.warning => colors.warning,
      UiStatusTone.danger => colors.danger,
      UiStatusTone.info => colors.info,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.appRadii.md),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: spacing.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: 0.72)),
            ),
          ),
          child: Row(
            children: [
              AppAvatar(
                label: item.user.displayName,
                imageUrl: item.user.avatarUrl,
                radius: 24,
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      item.subtitle.isEmpty
                          ? item.deviceSummary
                          : item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                    ),
                    SizedBox(height: spacing.xs),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: toneColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: spacing.xs),
                        Flexible(
                          child: Text(
                            item.badge.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: toneColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.sm),
              Icon(
                item.isCurrentUser
                    ? Icons.person_outline_rounded
                    : item.hasExistingConversation
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.chevron_right_rounded,
                size: item.hasExistingConversation ? 19 : 22,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

class _FilterOption<T> {
  const _FilterOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _FilterStrip<T> extends StatelessWidget {
  const _FilterStrip({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<_FilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < options.length; index++) ...[
            ChoiceChip(
              label: Text(options[index].label),
              selected: options[index].value == selected,
              onSelected: (_) => onSelected(options[index].value),
              showCheckmark: false,
              selectedColor: colors.primary,
              backgroundColor: colors.surfaceMuted,
              side: BorderSide(
                color: options[index].value == selected
                    ? colors.primary
                    : colors.border,
              ),
              labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: options[index].value == selected
                    ? Colors.white
                    : colors.textMuted,
                fontWeight: FontWeight.w700,
              ),
              padding: EdgeInsets.symmetric(horizontal: spacing.sm),
            ),
            if (index < options.length - 1) SizedBox(width: spacing.sm),
          ],
        ],
      ),
    );
  }
}

class _TabMeta {
  const _TabMeta({
    required this.label,
    required this.icon,
    required this.title,
  });

  final String label;
  final List<List<dynamic>> icon;
  final String title;
}

class _ContactDetailPage extends StatelessWidget {
  const _ContactDetailPage({
    required this.item,
    required this.detail,
    required this.onStartChat,
    required this.onVerify,
    required this.onRoleChanged,
  });

  final ContactListItemState item;
  final ContactDetailState detail;
  final Future<void> Function()? onStartChat;
  final Future<void> Function()? onVerify;
  final Future<void> Function(String role)? onRoleChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return AppScaffold(
      appBar: AppBar(title: const Text('Kontakt ma’lumotlari')),
      body: ListView(
        padding: EdgeInsets.all(spacing.lg),
        children: [
          AppSurfaceCard(
            child: Row(
              children: [
                AppAvatar(
                  label: item.user.displayName,
                  imageUrl: item.user.avatarUrl,
                  radius: 28,
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.user.displayName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        '${item.user.roleLabel} • ${item.user.username}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.lg),
          AppSurfaceCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.badge_outlined,
                color: context.appColors.primary,
              ),
              title: const Text('Korporativ roli'),
              subtitle: Text(item.user.roleLabel),
              trailing: onRoleChanged == null
                  ? null
                  : const Icon(Icons.chevron_right_rounded),
              onTap: onRoleChanged == null
                  ? null
                  : () => _showRolePicker(context),
            ),
          ),
          SizedBox(height: spacing.lg),
          AppBadge(
            label: detail.badge.label,
            tone: _mapTone(detail.badge.tone),
          ),
          SizedBox(height: spacing.md),
          AppStatusBanner(
            message: detail.badge.details ?? detail.deviceSummary,
            tone: _mapTone(detail.badge.tone),
          ),
          SizedBox(height: spacing.lg),
          const AppSectionHeader(
            title: 'Qurilmalar',
            subtitle: 'Kontaktning ko‘rinadigan qurilmalari.',
          ),
          SizedBox(height: spacing.sm),
          if (detail.devices.isEmpty)
            const AppEmptyState(
              message: 'Bu kontakt uchun ko‘rinadigan qurilma yo‘q.',
              icon: Icons.devices_outlined,
            )
          else
            for (final device in detail.devices)
              Padding(
                padding: EdgeInsets.only(bottom: spacing.sm),
                child: AppSurfaceCard(
                  child: Row(
                    children: [
                      const AppAvatar(
                        label: 'D',
                        icon: Icons.devices_outlined,
                        radius: 18,
                      ),
                      SizedBox(width: spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.deviceName.isEmpty
                                  ? device.deviceId
                                  : device.deviceName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            SizedBox(height: spacing.xs),
                            Text(
                              '${device.platform.isEmpty ? 'noma’lum' : device.platform} • ${device.isActive ? 'faol' : device.status} • ${device.hasUsableMlKemKey && device.hasUsableMlDsaKey ? 'tayyor' : 'tayyor emas'}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: context.appColors.textMuted,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          SizedBox(height: spacing.lg),
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton(
                  onPressed: item.isCurrentUser
                      ? null
                      : () async {
                          await onStartChat?.call();
                          if (context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                  label: Text(
                    detail.hasExistingConversation
                        ? 'Chatni ochish'
                        : 'Chat boshlash',
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: AppSecondaryButton(
                  onPressed: onVerify == null
                      ? null
                      : () async {
                          await onVerify!.call();
                          if (context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                  label: const Text('Kalitni tasdiqlash'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showRolePicker(BuildContext context) async {
    const roles = <(String, String, IconData)>[
      ('owner', 'Egasi', Icons.workspace_premium_outlined),
      ('admin', 'Administrator', Icons.admin_panel_settings_outlined),
      ('manager', 'Menejer', Icons.supervisor_account_outlined),
      ('member', 'Xodim', Icons.badge_outlined),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.appSpacing.md,
            0,
            context.appSpacing.md,
            context.appSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.all(context.appSpacing.sm),
                child: Text(
                  'Rolni tanlang',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final role in roles)
                ListTile(
                  leading: Icon(role.$3),
                  title: Text(role.$2),
                  trailing: item.user.role == role.$1
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: context.appColors.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(role.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != item.user.role) {
      await onRoleChanged!(selected);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  AppStatusTone _mapTone(UiStatusTone tone) {
    switch (tone) {
      case UiStatusTone.success:
        return AppStatusTone.success;
      case UiStatusTone.warning:
        return AppStatusTone.warning;
      case UiStatusTone.danger:
        return AppStatusTone.danger;
      case UiStatusTone.info:
        return AppStatusTone.info;
    }
  }
}
