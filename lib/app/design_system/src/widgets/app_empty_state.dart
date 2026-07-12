import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_surface_card.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    return AppSurfaceCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colors.surfaceMuted,
            child: Icon(icon, color: colors.textMuted),
          ),
          SizedBox(width: spacing.lg),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
