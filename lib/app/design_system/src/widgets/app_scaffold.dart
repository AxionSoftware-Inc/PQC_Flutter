import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.scaffoldKey,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      key: scaffoldKey,
      appBar: appBar,
      backgroundColor: colors.background,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
      bottomNavigationBar: bottomNavigationBar,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(colors.background, colors.primarySoft, 0.06)!,
              colors.background,
              colors.background,
            ],
            stops: const [0, 0.34, 1],
          ),
        ),
        child: body,
      ),
    );
  }
}
