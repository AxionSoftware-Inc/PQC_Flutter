import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppStatusTone { info, success, warning, danger }

class AppStatusBanner extends StatelessWidget {
  const AppStatusBanner({
    super.key,
    required this.message,
    this.tone = AppStatusTone.info,
    this.leading,
    this.action,
  });

  final String message;
  final AppStatusTone tone;
  final Widget? leading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final radii = context.appRadii;
    final (background, foreground, icon) = switch (tone) {
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
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radii.lg),
        border: Border.all(color: foreground.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading ??
              Icon(
                icon,
                color: foreground,
                size: 20,
              ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foreground,
              ),
            ),
          ),
          if (action != null) ...[
            SizedBox(width: spacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}
