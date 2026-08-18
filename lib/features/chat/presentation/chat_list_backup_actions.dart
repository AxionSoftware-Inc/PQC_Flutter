part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListBackupActions on _ChatListPageState {
  Future<void> _showExportBackupSheet() async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final spacing = context.appSpacing;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.lg,
              spacing.lg,
              spacing.lg + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  title: 'Shifrlangan zaxirani eksport qilish',
                  subtitle:
                      'Recovery passphrase bilan historical decrypt backup yaratiladi.',
                ),
                SizedBox(height: spacing.lg),
                AppTextField(
                  controller: controller,
                  labelText: 'Tiklash maxfiy iborasi',
                ),
                SizedBox(height: spacing.lg),
                AppPrimaryButton(
                  onPressed: () async {
                    final passphrase = controller.text.trim();
                    if (passphrase.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop();
                    final blob = await _controller.exportBackup(passphrase);
                    if (!mounted) {
                      return;
                    }
                    await _showBlobSheet(
                      title: 'Serverga saqlandi: encrypted backup blob',
                      blob: blob,
                    );
                  },
                  label: const Text('Zaxira yaratish'),
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
  }

  // ignore: unused_element
  Future<void> _showImportBackupSheet() async {
    final passphraseController = TextEditingController();
    final blobController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final spacing = context.appSpacing;
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.lg,
              spacing.lg,
              spacing.lg + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  title: 'Shifrlangan zaxirani import qilish',
                  subtitle:
                      'Old historical decrypt capability qayta tiklanadi.',
                ),
                SizedBox(height: spacing.lg),
                AppTextField(
                  controller: passphraseController,
                  labelText: 'Tiklash maxfiy iborasi',
                ),
                SizedBox(height: spacing.md),
                AppTextField(
                  controller: blobController,
                  labelText: 'Shifrlangan zaxira ma’lumoti',
                  maxLines: 8,
                  minLines: 6,
                ),
                SizedBox(height: spacing.md),
                AppSecondaryButton(
                  onPressed: () async {
                    final blob = await _controller.downloadServerBackup();
                    if (blob == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Serverda backup topilmadi.'),
                          ),
                        );
                      }
                      return;
                    }
                    blobController.text = blob;
                  },
                  label: const Text('Serverdan zaxirani yuklash'),
                ),
                SizedBox(height: spacing.lg),
                AppPrimaryButton(
                  onPressed: () async {
                    final passphrase = passphraseController.text.trim();
                    final blob = blobController.text.trim();
                    if (passphrase.isEmpty || blob.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop();
                    await _controller.importBackup(
                      recoveryPassphrase: passphrase,
                      encryptedBlob: blob,
                    );
                  },
                  label: const Text('Zaxirani tiklash'),
                ),
              ],
            ),
          ),
        );
      },
    );
    passphraseController.dispose();
    blobController.dispose();
  }

  Future<void> _showBlobSheet({
    required String title,
    required String blob,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final spacing = context.appSpacing;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionHeader(title: title),
                SizedBox(height: spacing.md),
                AppSurfaceCard(
                  child: SelectableText(
                    blob,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
