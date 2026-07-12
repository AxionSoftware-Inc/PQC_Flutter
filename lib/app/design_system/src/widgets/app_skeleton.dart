import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppSkeletonBlock extends StatelessWidget {
  const AppSkeletonBlock({
    super.key,
    this.height = 14,
    this.width,
    this.radius,
  });

  final double height;
  final double? width;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.appColors.surfaceMuted,
        borderRadius: BorderRadius.circular(radius ?? context.appRadii.md),
      ),
    );
  }
}
