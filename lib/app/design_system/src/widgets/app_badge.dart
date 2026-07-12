import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_status_banner.dart';

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppStatusTone.info,
    this.icon,
  });

  final String label;
  final AppStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final radii = context.appRadii;
    final (background, foreground, fallbackIcon) = switch (tone) {
      AppStatusTone.success => (
        colors.successSoft,
        colors.success,
        Icons.verified_rounded,
      ),
      AppStatusTone.warning => (
        colors.warningSoft,
        colors.warning,
        Icons.error_outline_rounded,
      ),
      AppStatusTone.danger => (
        colors.dangerSoft,
        colors.danger,
        Icons.report_gmailerrorred_rounded,
      ),
      AppStatusTone.info => (
        colors.infoSoft,
        colors.info,
        Icons.info_outline_rounded,
      ),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: spacing.sm, vertical: spacing.xs),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radii.pill),
        border: Border.all(color: foreground.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? fallbackIcon, color: foreground, size: 14),
          SizedBox(width: spacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
