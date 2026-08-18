import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../data/rbac_repository.dart';

part 'admin_panel_state.dart';
part 'admin_panel_actions.dart';
part 'admin_panel_role_mutations.dart';
part 'admin_panel_member_mutations.dart';
part 'admin_panel_views.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({
    super.key,
    required this.repository,
    this.standalone = true,
  });

  final RbacRepository repository;
  final bool standalone;

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}
