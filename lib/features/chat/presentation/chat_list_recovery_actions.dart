part of 'chat_list_page.dart';

// Extensions keep the page library cohesive while this file owns controller
// side effects that were previously mixed into the widget declaration.
// ignore_for_file: invalid_use_of_protected_member

extension _ChatListRecoveryActions on _ChatListPageState {
  Future<void> _syncServerRecovery() async {
    if (_recoveryPromptShown || !mounted) return;
    _recoveryPromptShown = true;
    await _controller.syncEnterpriseRecoveryManifest();
    if (mounted) await _controller.refresh();
  }

  Future<void> _showPendingRecoveryApprovals() async {
    final approvals = await _controller.pendingRecoveryApprovals();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Tarixni tiklash so‘rovlari'),
              subtitle: Text(
                'Faqat o‘zingiz taniydigan qurilmani tasdiqlang. Ruxsat muddati avtomatik tugaydi.',
              ),
            ),
            if (approvals.isEmpty)
              const ListTile(title: Text('Kutilayotgan so‘rov yo‘q')),
            for (final approval in approvals)
              ListTile(
                leading: const Icon(Icons.devices_other_outlined),
                title: Text(
                  approval['requesting_device_id'] as String? ??
                      'Yangi qurilma',
                ),
                subtitle: Text(
                  'So‘ralgan vaqt: ${approval['created_at'] ?? ''}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Rad etish',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () async {
                        await _controller.decideRecoveryApproval(
                          approvalId: approval['id'] as int,
                          approved: false,
                        );
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                    IconButton(
                      tooltip: 'Tasdiqlash',
                      icon: const Icon(Icons.check_rounded),
                      onPressed: () async {
                        await _controller.decideRecoveryApproval(
                          approvalId: approval['id'] as int,
                          approved: true,
                        );
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<String?> _showRecoveryPinDialog({required bool hasServerBackup}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          hasServerBackup
              ? 'Chat tarixini tiklash'
              : 'Chat tarixini himoyalash',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasServerBackup
                  ? 'Bu akkauntda shifrlangan tiklash nusxasi mavjud. Eski xabarlarni ochish uchun tiklash PIN kodini kiriting.'
                  : 'Tiklash PIN kodini yarating. U chat kalitlarini himoyalaydi va qayta o‘rnatishdan keyin tarixni tiklashga yordam beradi.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: const InputDecoration(labelText: 'Tiklash PIN kodi'),
            ),
          ],
        ),
        actions: [
          if (hasServerBackup)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Keyinroq'),
            ),
          FilledButton(
            onPressed: () {
              final pin = controller.text.trim();
              if (pin.length < 6) return;
              Navigator.of(dialogContext).pop(pin);
            },
            child: Text(hasServerBackup ? 'Tiklash' : 'Zaxirani saqlash'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}
