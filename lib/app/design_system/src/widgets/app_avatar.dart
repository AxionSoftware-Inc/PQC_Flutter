import 'package:flutter/material.dart';

import '../brand/app_brand_scope.dart';
import '../theme/app_theme.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.label,
    this.icon,
    this.radius = 22,
  });

  final String label;
  final IconData? icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = AppBrandScope.of(context).brand?.accentColor ?? colors.primary;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color.lerp(accent, Colors.white, 0.82),
      foregroundColor: accent,
      child: icon != null
          ? Icon(icon, size: radius)
          : Text(
              label.isEmpty ? '?' : label[0].toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
