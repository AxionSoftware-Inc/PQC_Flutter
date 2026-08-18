part of 'chat_page.dart';

class _SelectedAttachment {
  const _SelectedAttachment({
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
    this.bytes,
    this.filePath,
  });

  final String name;
  final List<int>? bytes;
  final String? filePath;
  final int sizeBytes;
  final String mimeType;

  bool get isImage => mimeType.startsWith('image/');
}

class _ComposerActionButton extends StatelessWidget {
  const _ComposerActionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(38),
        maximumSize: const Size.square(38),
        padding: EdgeInsets.zero,
        backgroundColor: context.appColors.surfaceMuted,
      ),
    );
  }
}

class _ComposerSendButton extends StatelessWidget {
  const _ComposerSendButton({required this.isSending, required this.onPressed});

  final bool isSending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: context.appDurations.fast,
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isSending
            ? context.appColors.primarySoft
            : context.appColors.primary,
        shape: BoxShape.circle,
        boxShadow: isSending ? const [] : context.appShadows.card,
      ),
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        color: Colors.white,
        icon: AnimatedSwitcher(
          duration: context.appDurations.fast,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: isSending
              ? SizedBox(
                  key: const ValueKey('sending'),
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.appColors.primary,
                  ),
                )
              : const Icon(Icons.send_rounded, key: ValueKey('send'), size: 18),
        ),
      ),
    );
  }
}
