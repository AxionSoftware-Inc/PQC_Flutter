part of 'chat_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatPageMessageActions on _ChatPageState {
  String _statusLabel(ChatMessage message) {
    switch (message.deliveryState) {
      case MessageDeliveryState.pending:
        return context.antiQText(uz: 'Yuborilmoqda...', en: 'Sending...');
      case MessageDeliveryState.failedRetryable:
        return message.failureReason ??
            context.antiQText(
              uz: 'Yuborilmadi. Qayta urinib ko‘ring.',
              en: 'Send failed. Try again.',
            );
      case MessageDeliveryState.failedPermanent:
        return message.failureReason ??
            context.antiQText(
              uz: 'Xabarni yuborib bo‘lmadi.',
              en: 'The message could not be sent.',
            );
      case MessageDeliveryState.sent:
        return '';
    }
  }

  Future<void> _showConversationDetails() {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: _ConversationProfilePage(
            title: widget.title,
            avatarUrl: widget.avatarUrl,
            roleLabel: widget.roleLabel,
            conversation: widget.conversation,
            trust: _controller.trust?.trust,
          ),
        ),
      ),
    );
  }
}
