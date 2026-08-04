import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.compact = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(context.appRadii.md),
        border: Border.all(color: colors.border.withValues(alpha: 0.58)),
      ),
      child: TextField(
        controller: controller,
        style: compact ? Theme.of(context).textTheme.bodyMedium : null,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: colors.textMuted),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: colors.textMuted,
            size: 21,
          ),
          prefixIconConstraints: compact
              ? const BoxConstraints(minWidth: 38, minHeight: 38)
              : null,
          contentPadding: compact
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 9)
              : null,
          isDense: compact,
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  visualDensity: compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        onChanged: onChanged,
      ),
    );
  }
}
