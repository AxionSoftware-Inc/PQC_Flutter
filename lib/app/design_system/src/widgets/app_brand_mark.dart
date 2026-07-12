import 'package:flutter/material.dart';

import '../brand/app_brand_scope.dart';
import '../theme/app_theme.dart';

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({
    super.key,
    this.size = 56,
    this.showWordmark = true,
  });

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final scope = AppBrandScope.of(context);
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final accent = scope.brand?.accentColor ?? colors.primary;
    final logoUrl = scope.brand?.logoUrl.isNotEmpty == true
        ? scope.brand!.logoUrl
        : scope.skin.logoUrl;
    final emblem = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(accent, Colors.white, 0.28)!,
            Color.lerp(accent, Colors.white, 0.62)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(context.appRadii.lg),
        boxShadow: context.appShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl.isNotEmpty
          ? Image.network(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _FallbackBrandGlyph(accent: accent, wordmark: scope.skin.wordmark),
            )
          : _FallbackBrandGlyph(accent: accent, wordmark: scope.skin.wordmark),
    );
    if (!showWordmark) {
      return emblem;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        emblem,
        SizedBox(width: spacing.md),
        Flexible(
          child: Text(
            scope.brand?.label.isNotEmpty == true
                ? scope.brand!.label
                : scope.skin.wordmark,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _FallbackBrandGlyph extends StatelessWidget {
  const _FallbackBrandGlyph({
    required this.accent,
    required this.wordmark,
  });

  final Color accent;
  final String wordmark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.appRadii.lg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        ),
        child: Center(
          child: Text(
            wordmark.isEmpty ? 'A' : wordmark[0].toUpperCase(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
