import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'design_system/app_design_system.dart';
import 'theme_controller.dart';
import '../features/auth/session_controller.dart';
import '../features/chat/application/chat_facade.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/chat/presentation/chat_list_page.dart';
import '../features/account/data/account_repository.dart';
import '../features/rbac/data/rbac_repository.dart';
import '../features/tasks/data/task_kpi_repository.dart';
import '../features/crypto/durability/crypto_core_facade.dart';
import '../core/database/app_database.dart';

class PqcChatApp extends StatelessWidget {
  const PqcChatApp({
    super.key,
    required this.sessionController,
    required this.chatFacade,
    required this.cryptoCoreFacade,
    required this.themeController,
    required this.skin,
    required this.accountRepository,
    required this.taskKpiRepository,
    required this.rbacRepository,
    required this.database,
  });

  final SessionController sessionController;
  final ChatFacade chatFacade;
  final CryptoCoreFacade cryptoCoreFacade;
  final AppThemeController themeController;
  final AppSkin skin;
  final AccountRepository accountRepository;
  final TaskKpiRepository taskKpiRepository;
  final RbacRepository rbacRepository;
  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([sessionController, themeController]),
      builder: (context, _) {
        final brand = WorkspaceBrandResolver.fromSession(
          sessionController.sessionUser,
        );
        return MaterialApp(
          title: skin.appTitle,
          debugShowCheckedModeBanner: false,
          locale: themeController.locale,
          supportedLocales: const [Locale('uz'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: themeController.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 280),
          themeAnimationCurve: Curves.easeOutCubic,
          theme: AppThemeFactory.build(skin: skin, brand: brand),
          darkTheme: AppThemeFactory.build(
            skin: skin,
            brand: brand,
            brightness: Brightness.dark,
          ),
          builder: (context, child) => AppBrandScope(
            skin: skin,
            brand: brand,
            child: child ?? const SizedBox.shrink(),
          ),
          home: Builder(
            builder: (context) {
              if (sessionController.isLoading) {
                return const _AntiQStartupView();
              }

              if (!sessionController.isAuthenticated) {
                return LoginPage(sessionController: sessionController);
              }

              return ChatListPage(
                sessionController: sessionController,
                chatFacade: chatFacade,
                cryptoCoreFacade: cryptoCoreFacade,
                themeController: themeController,
                accountRepository: accountRepository,
                taskKpiRepository: taskKpiRepository,
                rbacRepository: rbacRepository,
                database: database,
              );
            },
          ),
        );
      },
    );
  }
}

class _AntiQStartupView extends StatelessWidget {
  const _AntiQStartupView();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: ((value - 0.92) / 0.08).clamp(0, 1),
            child: Transform.scale(scale: value, child: child),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBrandMark(size: 76),
              SizedBox(height: 22),
              SizedBox(
                width: 112,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
