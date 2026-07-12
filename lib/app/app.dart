import 'package:flutter/material.dart';

import 'design_system/app_design_system.dart';
import 'theme_controller.dart';
import '../features/auth/session_controller.dart';
import '../features/chat/application/chat_facade.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/chat/presentation/chat_list_page.dart';
import '../features/crypto/durability/crypto_core_facade.dart';

class PqcChatApp extends StatelessWidget {
  const PqcChatApp({
    super.key,
    required this.sessionController,
    required this.chatFacade,
    required this.cryptoCoreFacade,
    required this.themeController,
    required this.skin,
  });

  final SessionController sessionController;
  final ChatFacade chatFacade;
  final CryptoCoreFacade cryptoCoreFacade;
  final AppThemeController themeController;
  final AppSkin skin;

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
          themeMode: themeController.themeMode,
          theme: AppThemeFactory.build(
            skin: skin,
            brand: brand,
          ),
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
                return const AppScaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (!sessionController.isAuthenticated) {
                return LoginPage(sessionController: sessionController);
              }

              return ChatListPage(
                sessionController: sessionController,
                chatFacade: chatFacade,
                cryptoCoreFacade: cryptoCoreFacade,
                themeController: themeController,
              );
            },
          ),
        );
      },
    );
  }
}
