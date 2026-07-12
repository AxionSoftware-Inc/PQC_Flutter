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
    final accent =
        _avatarAccent(label) ??
        AppBrandScope.of(context).brand?.accentColor ??
        colors.primary;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color.lerp(accent, colors.surface, 0.76),
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

  Color? _avatarAccent(String value) {
    if (value.trim().isEmpty) {
      return null;
    }
    const palette = <Color>[
      Color(0xFF2563EB),
      Color(0xFF0F766E),
      Color(0xFFB45309),
      Color(0xFFBE185D),
      Color(0xFF7C3AED),
      Color(0xFF047857),
      Color(0xFFB91C1C),
      Color(0xFF4338CA),
    ];
    final hash = value.trim().toLowerCase().codeUnits.fold<int>(
      0,
      (acc, item) => (acc * 31 + item) & 0x7fffffff,
    );
    return palette[hash % palette.length];
  }
}
