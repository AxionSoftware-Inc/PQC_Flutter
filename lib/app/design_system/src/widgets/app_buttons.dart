import 'package:flutter/material.dart';

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return FilledButton(onPressed: onPressed, child: label);
    }
    return FilledButton.icon(onPressed: onPressed, icon: icon!, label: label);
  }
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return OutlinedButton(onPressed: onPressed, child: label);
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon!,
      label: label,
    );
  }
}
