import 'package:flutter/material.dart';

import '../brand/app_brand_scope.dart';
import '../theme/app_theme.dart';

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.size = 56, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final scope = AppBrandScope.of(context);
    final spacing = context.appSpacing;
    final logoUrl = scope.brand?.logoUrl.isNotEmpty == true
        ? scope.brand!.logoUrl
        : scope.skin.logoUrl;
    final emblem = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF07090D),
        borderRadius: BorderRadius.circular(context.appRadii.lg),
        boxShadow: context.appShadows.card,
      ),
      padding: EdgeInsets.all(size * 0.13),
      clipBehavior: Clip.antiAlias,
      child: logoUrl.isNotEmpty
          ? Image.network(
              logoUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Image(
                image: AssetImage('assets/brand/antiq-mark-light.png'),
                fit: BoxFit.contain,
              ),
            )
          : const Image(
              image: AssetImage('assets/brand/antiq-mark-light.png'),
              fit: BoxFit.contain,
            ),
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
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.7,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
