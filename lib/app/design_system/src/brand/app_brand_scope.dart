import 'package:flutter/widgets.dart';

import 'app_brand.dart';

class AppBrandScope extends InheritedWidget {
  const AppBrandScope({
    super.key,
    required this.skin,
    required this.brand,
    required super.child,
  });

  final AppSkin skin;
  final ResolvedWorkspaceBrand? brand;

  static AppBrandScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppBrandScope>();
    if (scope == null) {
      throw StateError('AppBrandScope is missing in the widget tree.');
    }
    return scope;
  }

  static AppBrandScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppBrandScope>();
  }

  @override
  bool updateShouldNotify(AppBrandScope oldWidget) {
    return oldWidget.skin != skin || oldWidget.brand != brand;
  }
}
