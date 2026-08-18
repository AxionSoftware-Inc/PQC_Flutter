part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListSettingsSections on _ChatListPageState {
  Widget _settingsSection(
    String title,
    String subtitle,
    IconData icon,
    Widget Function(SettingsViewState) builder,
  ) {
    final spacing = context.appSpacing;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(context.appRadii.md),
        onTap: () => Navigator.of(context).push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 220),
            reverseTransitionDuration: const Duration(milliseconds: 180),
            pageBuilder: (_, animation, _) {
              final curve = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );
              return FadeTransition(
                opacity: curve,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.015, 0.02),
                    end: Offset.zero,
                  ).animate(curve),
                  child: _SettingsPage(
                    title: title,
                    child: ListenableBuilder(
                      listenable: _controller,
                      builder: (_, _) => builder(_controller.settingsState),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: context.appColors.border.withValues(alpha: 0.65),
              ),
            ),
          ),
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            contentPadding: EdgeInsets.symmetric(horizontal: spacing.xs),
            leading: Icon(icon, color: context.appColors.primary),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ),
    );
  }

  Widget _settingsList(List<Widget> children) => ListView(
    padding: EdgeInsets.all(context.appSpacing.md),
    children: children,
  );
}
