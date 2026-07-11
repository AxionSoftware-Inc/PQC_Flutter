import 'package:flutter/material.dart';

import '../features/auth/session_controller.dart';
import '../features/chat/application/chat_facade.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/chat/presentation/chat_list_page.dart';

class PqcChatApp extends StatelessWidget {
  const PqcChatApp({
    super.key,
    required this.sessionController,
    required this.chatFacade,
  });

  final SessionController sessionController;
  final ChatFacade chatFacade;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PQC Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: AnimatedBuilder(
        animation: sessionController,
        builder: (context, _) {
          if (sessionController.isLoading) {
            return const Scaffold(
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
    );
  }
}
