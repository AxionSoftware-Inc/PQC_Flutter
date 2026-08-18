part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListSessionActions on _ChatListPageState {
  Future<void> _logout({required bool forgetDevice}) async {
    if (forgetDevice) {
      await widget.sessionController.logoutAndForgetDevice();
    } else {
      await widget.sessionController.logout();
    }
  }

  void _openProfile(SettingsViewState state) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Profil')),
          body: SafeArea(child: _buildAccountTab(state)),
        ),
      ),
    );
  }

  void _showMessage(String message, {required AppStatusTone tone}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: switch (tone) {
          AppStatusTone.success => context.appColors.success,
          AppStatusTone.warning => context.appColors.warning,
          AppStatusTone.danger => context.appColors.danger,
          AppStatusTone.info => context.appColors.info,
        },
      ),
    );
  }
}
