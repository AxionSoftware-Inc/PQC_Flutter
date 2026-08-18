part of 'chat_list_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatListSecuritySettings on _ChatListPageState {
  Widget _buildSecuritySettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Xavfsizlik markazi',
        subtitle: 'Ishonch va eski xabarlarni ochish tayyorligi.',
      ),
      SizedBox(height: spacing.sm),
      AppSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: spacing.sm,
              runSpacing: spacing.sm,
              children: [
                AppBadge(
                  label: '${state.security.verifiedPeersCount} tasdiqlangan',
                  tone: AppStatusTone.success,
                ),
                AppBadge(
                  label:
                      '${state.security.needsAttentionCount} e’tibor talab qiladi',
                  tone: AppStatusTone.warning,
                ),
                AppBadge(
                  label: '${state.security.notReadyCount} tayyor emas',
                  tone: AppStatusTone.danger,
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            AppStatusBanner(
              message: state.security.hasHistoricalDecryptCapability
                  ? 'Eski xabarlarni ochish tayyor. ${state.security.availableHistoricalKeysets} ta kalitlar to‘plami mavjud.'
                  : 'Eski xabarlarni ochish cheklangan. Eski xabarlar uchun zaxirani tiklang.',
              tone: state.security.hasHistoricalDecryptCapability
                  ? AppStatusTone.success
                  : AppStatusTone.warning,
            ),
            SizedBox(height: spacing.sm),
            AppStatusBanner(
              message: state.security.isCurrentDeviceReady
                  ? 'Bu qurilma xavfsiz xabar almashishga tayyor.'
                  : 'Bu qurilmada kalitlarni sozlash kerak.',
              tone: state.security.isCurrentDeviceReady
                  ? AppStatusTone.success
                  : AppStatusTone.warning,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildDevicesSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Qurilmalar va seanslar',
        subtitle: 'Faqat o‘zingiz tanimaydigan qurilmalarni bekor qiling.',
      ),
      SizedBox(height: spacing.sm),
      for (final device in state.devices)
        Padding(
          padding: EdgeInsets.only(bottom: spacing.sm),
          child: AppSurfaceCard(
            child: ListTile(
              leading: Icon(
                device.deviceId == state.sessionUser.deviceId
                    ? Icons.phone_android_rounded
                    : Icons.devices_outlined,
              ),
              title: Text(
                device.deviceName.isEmpty ? device.deviceId : device.deviceName,
              ),
              subtitle: Text(
                '${device.platform.isEmpty ? 'Noma’lum platforma' : device.platform} • ${device.status}',
              ),
              trailing: device.deviceId == state.sessionUser.deviceId
                  ? const AppBadge(
                      label: 'Bu qurilma',
                      tone: AppStatusTone.info,
                    )
                  : IconButton(
                      tooltip: 'Qurilmani bekor qilish',
                      icon: Icon(
                        Icons.remove_circle_outline_rounded,
                        color: context.appColors.danger,
                      ),
                      onPressed: () => _confirmDeviceRevoke(device),
                    ),
            ),
          ),
        ),
      if (state.devices.isEmpty)
        _buildEmptyCard('Ro‘yxatdan o‘tgan qurilma topilmadi.'),
    ]);
  }

  Widget _buildBackupSettings(SettingsViewState state) {
    final spacing = context.appSpacing;
    return _settingsList([
      const AppSectionHeader(
        title: 'Zaxira va tiklash',
        subtitle:
            'Qayta o‘rnatish yoki qurilma almashtirishdan keyin tarixni tiklash.',
      ),
      SizedBox(height: spacing.sm),
      if (state.backup.statusMessage != null)
        AppStatusBanner(
          message: state.backup.statusMessage!,
          tone: _statusTone(state.backup.statusTone),
        ),
      AppSurfaceCard(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Shifrlangan tarixni tiklash'),
              subtitle: const Text(
                'Tasdiqlangandan keyin akkaunt tiklash ma’lumotini import qiling.',
              ),
              onTap: _restoreEnterpriseRecovery,
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Tiklash ruxsatlari'),
              subtitle: const Text(
                'Boshqa qurilmalaringiz so‘rovlarini ko‘ring.',
              ),
              onTap: _showPendingRecoveryApprovals,
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Shifrlangan zaxirani eksport qilish'),
              onTap: _showExportBackupSheet,
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Shifrlangan zaxirani import qilish'),
              onTap: _showImportBackupSheet,
            ),
          ],
        ),
      ),
    ]);
  }

  Future<void> _restoreEnterpriseRecovery() async {
    try {
      await _controller.restoreEnterpriseRecovery();
    } catch (error) {
      if (mounted) _showMessage(error.toString(), tone: AppStatusTone.danger);
    }
  }

  Future<void> _confirmDeviceRevoke(AppUserDevice device) async {
    final label = device.deviceName.isEmpty
        ? device.deviceId
        : device.deviceName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Qurilma bekor qilinsinmi?'),
        content: Text('$label endi bu akkauntga kira olmaydi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bekor qilishni tasdiqlash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _controller.revokeDevice(device.deviceId);
      if (mounted) {
        _showMessage('Qurilma bekor qilindi.', tone: AppStatusTone.success);
      }
    } catch (error) {
      if (mounted) _showMessage(error.toString(), tone: AppStatusTone.danger);
    }
  }
}
