part of 'chat_hub_controller.dart';

mixin _ChatHubBackupActions on _ChatHubControllerBase {
  Future<void> refresh();

  Future<String> exportBackup(String recoveryPassphrase) async {
    final blob = await cryptoCoreFacade.exportEncryptedBackup(
      BackupExportRequest(recoveryPassphrase: recoveryPassphrase),
    );
    final bytes = utf8.encode(blob);
    await accountRepository.put('/users/me/crypto-backup', {
      'version': 1,
      'encrypted_blob': blob,
      'blob_sha256': sha256.convert(bytes).toString(),
    });
    _backupState = _backupState.copyWith(
      lastExportedBlob: blob,
      statusMessage: 'Encrypted backup tayyor bo‘ldi.',
      statusTone: UiStatusTone.success,
    );
    notifyListeners();
    return blob;
  }

  Future<String?> downloadServerBackup() async {
    final response = await accountRepository.get('/users/me/crypto-backup');
    if (response is! Map || response['available'] != true) return null;
    final blob = response['encrypted_blob'] as String?;
    if (blob == null || blob.isEmpty) return null;
    return blob;
  }

  Future<void> syncEnterpriseRecoveryManifest() async {
    final response = await accountRepository.get(
      '/users/me/crypto-recovery',
      queryParameters: const {'metadata_only': 'true'},
      includeRecoveryCredentials: true,
    );
    final sequence = response is Map && response['available'] == true
        ? response['sequence'] as int? ?? 0
        : 0;
    await _publishEnterpriseRecoverySnapshot(expectedSequence: sequence);
    _backupState = _backupState.copyWith(
      statusMessage:
          'Enterprise recovery snapshot is synchronized. Restore history explicitly from Security when needed.',
      statusTone: UiStatusTone.success,
    );
    notifyListeners();
  }

  /// Explicit user action: the app must never silently import escrowed keys
  /// while merely opening a chat list on a newly installed device.
  Future<void> restoreEnterpriseRecovery() async {
    Map<String, String>? queryParameters;
    final challenge = _recoveryApprovalChallenge;
    if (challenge != null && challenge.isNotEmpty) {
      queryParameters = {'approval': challenge};
    }
    dynamic response;
    try {
      response = await accountRepository.get(
        '/users/me/crypto-recovery',
        queryParameters: queryParameters,
        includeRecoveryCredentials: true,
      );
    } on ApiException catch (error) {
      if (error.code != 'recovery_approval_required') rethrow;
      final approval =
          await accountRepository.post('/users/me/crypto-recovery/approvals', {
                'requester_device_id': sessionUserProvider().deviceId,
              }, includeRecoveryCredentials: true)
              as Map<String, dynamic>;
      _recoveryApprovalChallenge = approval['challenge'] as String?;
      _backupState = _backupState.copyWith(
        statusMessage:
            'Recovery request sent. Approve it from another active device, then press Restore again.',
        statusTone: UiStatusTone.warning,
      );
      notifyListeners();
      return;
    }
    if (response is! Map || response['available'] != true) {
      throw ApiException('No enterprise recovery manifest is available.');
    }
    final records = response['records'] as List<dynamic>? ?? const [];
    if (records.isEmpty) {
      throw ApiException('Enterprise recovery manifest has no records.');
    }
    for (final record in records) {
      final payload = (record as Map)['payload'] as String?;
      if (payload != null && payload.isNotEmpty) {
        await cryptoCoreFacade.importEnterpriseRecoveryManifest(payload);
      }
    }
    final historical = await cryptoCoreFacade.historicalDecryptCheck();
    _securityState = _securityState.copyWith(
      hasHistoricalDecryptCapability: historical.hasHistoricalCapability,
      availableHistoricalKeysets: historical.availableKeysets,
    );
    _backupState = _backupState.copyWith(
      statusMessage: 'Enterprise history recovery completed.',
      statusTone: UiStatusTone.success,
    );
    await refresh();
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> pendingRecoveryApprovals() async {
    final response = await accountRepository.get(
      '/users/me/crypto-recovery/approvals',
      includeRecoveryCredentials: true,
    );
    if (response is! Map) return const [];
    return (response['approvals'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  Future<void> decideRecoveryApproval({
    required int approvalId,
    required bool approved,
  }) {
    return accountRepository.post(
      '/users/me/crypto-recovery/approvals/$approvalId',
      {
        'approver_device_id': sessionUserProvider().deviceId,
        'approved': approved,
      },
      includeRecoveryCredentials: true,
    );
  }

  Future<void> _publishEnterpriseRecoverySnapshot({
    required int expectedSequence,
  }) async {
    final payload = await cryptoCoreFacade.exportEnterpriseRecoveryManifest();
    final deviceId = sessionUserProvider().deviceId;
    try {
      await accountRepository.put('/users/me/crypto-recovery', {
        'schema_version': 2,
        'payload': payload,
        'source_device_id': deviceId,
        'expected_sequence': expectedSequence,
      }, includeRecoveryCredentials: true);
    } on ApiException catch (error) {
      if (error.code != 'recovery_manifest_conflict') rethrow;
      final latest = await accountRepository.get(
        '/users/me/crypto-recovery',
        queryParameters: const {'metadata_only': 'true'},
        includeRecoveryCredentials: true,
      );
      if (latest is! Map || latest['available'] != true) rethrow;
      await accountRepository.put('/users/me/crypto-recovery', {
        'schema_version': 2,
        'payload': payload,
        'source_device_id': deviceId,
        'expected_sequence': latest['sequence'] as int? ?? 0,
      }, includeRecoveryCredentials: true);
    }
  }

  Future<void> importBackup({
    required String recoveryPassphrase,
    required String encryptedBlob,
  }) async {
    try {
      await cryptoCoreFacade.importEncryptedBackup(
        BackupImportRequest(
          recoveryPassphrase: recoveryPassphrase,
          encryptedBlob: encryptedBlob.trim(),
        ),
      );
      final historical = await cryptoCoreFacade.historicalDecryptCheck();
      _securityState = _securityState.copyWith(
        hasHistoricalDecryptCapability: historical.hasHistoricalCapability,
        availableHistoricalKeysets: historical.availableKeysets,
      );
      _backupState = _backupState.copyWith(
        statusMessage: 'Backup muvaffaqiyatli tiklandi.',
        statusTone: UiStatusTone.success,
      );
    } catch (error) {
      final message = error.toString().toLowerCase();
      final normalized = message.contains('passphrase')
          ? 'Recovery passphrase noto‘g‘ri.'
          : message.contains('corrupted')
          ? 'Backup blob buzilgan.'
          : message.contains('unsupported')
          ? 'Backup versiyasi qo‘llab-quvvatlanmaydi.'
          : error.toString();
      _backupState = _backupState.copyWith(
        statusMessage: normalized,
        statusTone: UiStatusTone.danger,
      );
    }
    notifyListeners();
  }

  Future<void> clearBackupFeedback() async {
    _backupState = const BackupRecoveryState();
    notifyListeners();
  }
}
