import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppSurfaceCard extends StatelessWidget {
  const AppSurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radii = context.appRadii;
    final spacing = context.appSpacing;
    final content = Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface,
        borderRadius: BorderRadius.circular(radii.lg),
        border: Border.all(color: colors.border.withValues(alpha: 0.82)),
        boxShadow: context.appShadows.card,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(spacing.lg),
        child: child,
      ),
    );
    if (onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radii.lg),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
