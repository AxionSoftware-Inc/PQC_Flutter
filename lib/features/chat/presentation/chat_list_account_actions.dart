part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListAccountActions on _ChatListPageState {
  Future<void> _switchWorkspace(int workspaceId) async {
    await widget.sessionController.switchWorkspace(workspaceId);
    widget.chatFacade.switchWorkspaceContext(workspaceId);
    await _load();
  }

  Future<void> _showEditProfile() async {
    final session = widget.sessionController.sessionUser!;
    final nameController = TextEditingController(text: session.displayName);
    PlatformFile? selectedAvatar;
    var isSaving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                context.appSpacing.lg,
                context.appSpacing.xs,
                context.appSpacing.lg,
                MediaQuery.viewInsetsOf(sheetContext).bottom +
                    context.appSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: isSaving
                        ? null
                        : () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: const [
                                'jpg',
                                'jpeg',
                                'png',
                                'webp',
                              ],
                              withData: true,
                            );
                            final file = result?.files.singleOrNull;
                            if (file == null) {
                              return;
                            }
                            if (file.size > 5 * 1024 * 1024) {
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Rasm hajmi 5 MB dan oshmasligi kerak.',
                                      ),
                                    ),
                                  );
                              }
                              return;
                            }
                            setSheetState(() => selectedAvatar = file);
                          },
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        if (selectedAvatar?.bytes != null)
                          ClipOval(
                            child: SizedBox.square(
                              dimension: 84,
                              child: Image.memory(
                                selectedAvatar!.bytes!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        else
                          AppAvatar(
                            label: session.displayName,
                            imageUrl: session.avatarUrl,
                            radius: 42,
                          ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: context.appColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: context.appColors.surface,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.photo_camera_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: context.appSpacing.md),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Ism va familiya',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  SizedBox(height: context.appSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final name = nameController.text.trim();
                              if (name.length < 2) {
                                return;
                              }
                              setSheetState(() => isSaving = true);
                              try {
                                await widget.sessionController.updateProfile(
                                  displayName: name,
                                  avatarBytes: selectedAvatar?.bytes,
                                  avatarFilename: selectedAvatar?.name ?? '',
                                );
                                await _controller.refresh();
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              } catch (error) {
                                if (sheetContext.mounted) {
                                  ScaffoldMessenger.of(sheetContext)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(
                                      SnackBar(content: Text(error.toString())),
                                    );
                                  setSheetState(() => isSaving = false);
                                }
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Saqlash'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(nameController.dispose);
  }

  // ignore: unused_element
}
