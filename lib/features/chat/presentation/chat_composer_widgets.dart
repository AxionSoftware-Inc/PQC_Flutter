import 'package:flutter/material.dart';

class ChatComposerActionButton extends StatelessWidget {
  const ChatComposerActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(36),
        maximumSize: const Size.square(36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class ChatComposerSendButton extends StatelessWidget {
  const ChatComposerSendButton({
    super.key,
    required this.isSending,
    required this.onPressed,
  });

  final bool isSending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: isSending
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.arrow_upward_rounded, size: 18),
    );
  }
}
