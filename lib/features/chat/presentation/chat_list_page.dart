import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/app_localization.dart';
import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import 'package:chat_core/chat_core.dart' show UnauthorizedApiException;
import '../../account/data/account_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/storage/local_ui_preferences_store.dart';
import '../../../app/theme_controller.dart';
import '../../auth/session_controller.dart';
import '../../chat/application/chat_facade.dart';
import '../../crypto/durability/crypto_core_facade.dart';
import '../../rbac/presentation/admin_panel_page.dart';
import '../../rbac/data/rbac_repository.dart';
import '../../tasks/presentation/task_kpi_page.dart';
import '../../tasks/data/task_kpi_repository.dart';
import 'chat_hub_controller.dart';
import 'chat_page.dart';

part 'chat_list_state.dart';
part 'chat_list_state_actions.dart';
part 'chat_list_recovery_actions.dart';
part 'chat_list_navigation_actions.dart';
part 'chat_list_account_actions.dart';
part 'chat_list_backup_actions.dart';
part 'chat_list_session_actions.dart';
part 'chat_list_state_views.dart';
part 'chat_list_conversation_views.dart';
part 'chat_list_conversation_actions.dart';
part 'chat_list_contact_views.dart';
part 'chat_list_settings_views.dart';
part 'chat_list_settings_sections.dart';
part 'chat_list_account_settings.dart';
part 'chat_list_security_settings.dart';
part 'chat_list_preferences_settings.dart';
part 'chat_list_conversation_widgets.dart';
part 'chat_list_navigation_widgets.dart';
part 'chat_list_contact_widgets.dart';
part 'chat_list_contact_detail.dart';

/// RBAC is an optional business module.  Keeping the entry point behind a
/// compile-time flag lets the base messenger run without its backend plugin.
const _rbacModuleEnabled = bool.fromEnvironment(
  'RBAC_MODULE',
  // The production app ships with the RBAC plugin enabled. Deployments that
  // do not expose /rbac can still hide the tab through the server response.
  defaultValue: true,
);
const _taskKpiModuleEnabled = bool.fromEnvironment(
  'TASK_KPI_MODULE',
  defaultValue: true,
);

class ChatListPage extends StatefulWidget {
  const ChatListPage({
    super.key,
    required this.sessionController,
    required this.chatFacade,
    required this.cryptoCoreFacade,
    required this.themeController,
    required this.accountRepository,
    required this.taskKpiRepository,
    required this.rbacRepository,
    required this.database,
  });

  final SessionController sessionController;
  final ChatFacade chatFacade;
  final CryptoCoreFacade cryptoCoreFacade;
  final AppThemeController themeController;
  final AccountRepository accountRepository;
  final TaskKpiRepository taskKpiRepository;
  final RbacRepository rbacRepository;
  final AppDatabase database;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}
