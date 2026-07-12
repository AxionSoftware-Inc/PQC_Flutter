import 'package:flutter/material.dart';

import 'design_system/app_design_system.dart';
import '../features/auth/session_controller.dart';
import '../features/chat/application/chat_facade.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/chat/presentation/chat_list_page.dart';

class PqcChatApp extends StatelessWidget {
  const PqcChatApp({
    super.key,
    required this.sessionController,
    required this.chatFacade,
    required this.skin,
  });

  final SessionController sessionController;
  final ChatFacade chatFacade;
  final AppSkin skin;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sessionController,
      builder: (context, _) {
        final brand = WorkspaceBrandResolver.fromSession(
          sessionController.sessionUser,
        );
        return MaterialApp(
          title: skin.appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppThemeFactory.build(
            skin: skin,
            brand: brand,
          ),
          home: AppBrandScope(
            skin: skin,
            brand: brand,
            child: Builder(
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
                );
              },
            ),
          ),
        );
      },
    );
  }
}
