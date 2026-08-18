import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';

import '../../../app/app_localization.dart';
import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/app_user.dart';

part 'access_control_state.dart';
part 'access_control_views.dart';
part 'access_control_actions.dart';
part 'access_control_helpers.dart';

class AccessControlSettingsPage extends StatefulWidget {
  const AccessControlSettingsPage({
    super.key,
    required this.repository,
    required this.users,
  });

  final AccessControlRepository repository;
  final List<AppUser> users;

  @override
  State<AccessControlSettingsPage> createState() =>
      _AccessControlSettingsPageState();
}
