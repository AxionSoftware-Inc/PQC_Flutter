import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:crypto_core/crypto_core.dart' show Conversation;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/design_system/app_design_system.dart';
import '../data/task_kpi_repository.dart';
import '../../chat/presentation/chat_thread_widget.dart';

/// Optional task-center shell. Its APIs are supplied by the independent
/// `task_kpi` backend plugin, not by chat or crypto core. The future KPI app
/// can reuse the backend goal/scoring APIs without coupling them to this UI.

part 'task_detail_page.dart';
part 'task_create_page.dart';
part 'task_create_actions.dart';
part 'task_create_views.dart';
part 'task_create_helpers.dart';
part 'task_detail_actions.dart';
part 'task_detail_views.dart';
part 'task_detail_comments.dart';
part 'task_detail_files.dart';
part 'task_detail_activity_views.dart';
part 'task_kpi_state.dart';
part 'task_kpi_data_actions.dart';
part 'task_kpi_dashboard_views.dart';
part 'task_kpi_views.dart';
part 'task_kpi_analytics_views.dart';
part 'task_kpi_analytics_filters.dart';
part 'task_kpi_task_actions.dart';

class TaskKpiPage extends StatefulWidget {
  const TaskKpiPage({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.onOpenTaskChat,
  });

  final TaskKpiRepository repository;
  final int currentUserId;
  final Future<void> Function(Conversation conversation, String title)
  onOpenTaskChat;

  @override
  State<TaskKpiPage> createState() => _TaskKpiPageState();
}
