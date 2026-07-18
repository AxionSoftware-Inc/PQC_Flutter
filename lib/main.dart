import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:crypto_core/crypto_core.dart'
    show GroupCipherMessageCodec, PqcPrivateMessageCodec, V3ChatCipherAlgorithm;

import 'app/app.dart';
import 'app/design_system/app_design_system.dart';
import 'app/theme_controller.dart';
import 'core/database/app_database.dart';
import 'core/device/device_identity_service.dart';
import 'core/device/device_key_service.dart';
import 'core/device/device_pqc_key_service.dart';
import 'core/device/device_pqc_signing_key_service.dart';
import 'core/device/device_state_manager.dart';
import 'core/device/device_security_state_service.dart';
import 'core/network/api_client.dart';
import 'core/storage/local_data_protector.dart';
import 'core/storage/session_storage.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/session_controller.dart';
import 'features/chat/application/chat_facade.dart';
import 'features/chat/application/chat_local_store.dart';
import 'features/chat/application/chat_services.dart';
import 'features/chat/data/chat_remote_data_source.dart';
import 'features/chat/data/chat_realtime_service.dart';
import 'features/chat/data/outbox_store.dart';
import 'features/chat/data/private_conversation_security_coordinator.dart';
import 'features/crypto/chat_cipher_algorithms.dart';
import 'features/crypto/chat_cipher_service.dart';
import 'features/crypto/durability/crypto_backup_service.dart';
import 'features/crypto/durability/crypto_core_facade.dart';
import 'features/crypto/durability/key_material_registry.dart';
import 'features/crypto/durability/enterprise_recovery_sync_service.dart';
import 'features/crypto/group_key_store.dart';
import 'features/crypto/outbound_message_cache.dart';
import 'features/security/key_verification_service.dart';
import 'features/transfers/application/attachment_transfer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const skinId = String.fromEnvironment(
    'APP_SKIN',
    defaultValue: AppSkinRegistry.defaultSkinId,
  );

  final themeController = AppThemeController();
  final sessionStorage = SessionStorage();
  final appDatabase = AppDatabase();
  final localDataProtector = LocalDataProtector();
  final apiClient = ApiClient();
  final deviceIdentityService = DeviceIdentityService();
  final deviceKeyService = DeviceKeyService();
  final devicePqcKeyService = DevicePqcKeyService();
  final devicePqcSigningKeyService = DevicePqcSigningKeyService();
  final deviceSecurityStateService = DeviceSecurityStateService();
  final deviceStateManager = DeviceStateManager(
    deviceIdentityService: deviceIdentityService,
    deviceKeyService: deviceKeyService,
    devicePqcKeyService: devicePqcKeyService,
    devicePqcSigningKeyService: devicePqcSigningKeyService,
    deviceSecurityStateService: deviceSecurityStateService,
  );
  final outboundMessageCache = OutboundMessageCache();
  final remoteDataSource = ChatRemoteDataSource(apiClient: apiClient);
  final outboxStore = OutboxStore(
    database: appDatabase,
    localDataProtector: localDataProtector,
  );
  final keyVerificationService = KeyVerificationService(database: appDatabase);
  final keyMaterialRegistry = KeyMaterialRegistry(
    deviceIdentityService: deviceIdentityService,
    deviceKeyService: deviceKeyService,
    devicePqcKeyService: devicePqcKeyService,
    devicePqcSigningKeyService: devicePqcSigningKeyService,
  );
  final groupKeyStore = GroupKeyStore(
    deviceIdentityService: deviceIdentityService,
    devicePqcKeyService: devicePqcKeyService,
    devicePqcSigningKeyService: devicePqcSigningKeyService,
    remoteDataSource: remoteDataSource,
  );
  final authRepository = AuthRepository(
    apiClient: apiClient,
    sessionStorage: sessionStorage,
    deviceIdentityService: deviceIdentityService,
    deviceKeyService: deviceKeyService,
    devicePqcKeyService: devicePqcKeyService,
    devicePqcSigningKeyService: devicePqcSigningKeyService,
    deviceSecurityStateService: deviceSecurityStateService,
    deviceStateManager: deviceStateManager,
    appDatabase: appDatabase,
    outboundMessageCache: outboundMessageCache,
    outboxStore: outboxStore,
  );
  final chatRealtimeService = ChatRealtimeService(apiClient: apiClient);
  const enableV3Writer = bool.fromEnvironment('V3_WRITER', defaultValue: false);
  final cipherAlgorithms = <ChatCipherAlgorithm>[
    if (enableV3Writer)
      V3ChatCipherAlgorithm(
        identityService: deviceIdentityService,
        pqcKeyService: devicePqcKeyService,
        signingKeyService: devicePqcSigningKeyService,
        keyMaterialRegistry: keyMaterialRegistry,
      ),
    GroupChatCipherAlgorithm(
      groupKeyStore: groupKeyStore,
      codec: GroupCipherMessageCodec(groupKeyStore: groupKeyStore),
    ),
    PqcPrivateChatAlgorithm(
      deviceIdentityService: deviceIdentityService,
      devicePqcKeyService: devicePqcKeyService,
      devicePqcSigningKeyService: devicePqcSigningKeyService,
      keyMaterialRegistry: keyMaterialRegistry,
      codec: PqcPrivateMessageCodec(
        deviceIdentityService: deviceIdentityService,
        devicePqcKeyService: devicePqcKeyService,
        devicePqcSigningKeyService: devicePqcSigningKeyService,
        keyMaterialRegistry: keyMaterialRegistry,
      ),
    ),
  ];
  final chatCipherService = RoutedChatCipherService(
    algorithms: cipherAlgorithms,
    outboundMessageCache: outboundMessageCache,
  );
  final cryptoCoreFacade = CryptoCoreFacade(
    cipherService: chatCipherService,
    groupKeyStore: groupKeyStore,
    keyMaterialRegistry: keyMaterialRegistry,
    backupService: CryptoBackupService(
      keyMaterialRegistry: keyMaterialRegistry,
    ),
  );
  final enterpriseRecoverySyncService = EnterpriseRecoverySyncService(
    apiClient: apiClient,
    cryptoCoreFacade: cryptoCoreFacade,
    deviceIdentityService: deviceIdentityService,
  );
  final privateConversationSecurityCoordinator =
      PrivateConversationSecurityCoordinator(
        keyVerificationService: keyVerificationService,
      );
  final chatCryptoService = ChatCryptoService(
    cipherService: chatCipherService,
    cryptoCoreFacade: cryptoCoreFacade,
  );
  final attachmentTransferFacade = AttachmentTransferFacade(
    remoteDataSource: remoteDataSource,
  );
  final chatFacade = ChatFacade(
    remoteDataSource: remoteDataSource,
    realtimeService: chatRealtimeService,
    outboxStore: outboxStore,
    localStore: ChatLocalStore(
      database: appDatabase,
      localDataProtector: localDataProtector,
    ),
    trustService: ChatTrustService(
      keyVerificationService: keyVerificationService,
      privateConversationSecurityCoordinator:
          privateConversationSecurityCoordinator,
    ),
    cryptoService: chatCryptoService,
    attachmentTransferFacade: attachmentTransferFacade,
    onCryptoStateChanged: enterpriseRecoverySyncService.publishInBackground,
  );
  final sessionController = SessionController(
    authRepository: authRepository,
    onSessionChanged: (sessionUser) async {
      chatFacade.switchWorkspaceContext(sessionUser?.activeWorkspaceId ?? 0);
      if (sessionUser == null ||
          sessionUser.token.isEmpty ||
          sessionUser.activeWorkspaceId <= 0) {
        await chatRealtimeService.disconnect();
        return;
      }
      await cryptoCoreFacade.activateAccount('${sessionUser.accountId}');
      // Restore retained keysets before creating/registering a fresh
      // installation keyset.  A reinstall has a different device id, but it
      // must still be able to decrypt wraps addressed to the prior device.
      await enterpriseRecoverySyncService.restoreIfAvailable();
      await cryptoCoreFacade.initialize();
      // Finish the account recovery snapshot before the app becomes usable.
      // This closes the uninstall/reinstall race where a newly-created keyset
      // had not reached the server yet.
      try {
        await enterpriseRecoverySyncService.publishInBackground();
      } catch (_) {
        // Login remains usable; the next lifecycle/send retries publication.
      }
      await chatRealtimeService.connect(
        token: sessionUser.token,
        workspaceId: '${sessionUser.activeWorkspaceId}',
        deviceId: sessionUser.deviceId,
      );
      unawaited(chatFacade.resumePendingWork(currentUserId: sessionUser.id));
    },
  );

  runApp(
    PqcChatApp(
      sessionController: sessionController,
      chatFacade: chatFacade,
      cryptoCoreFacade: cryptoCoreFacade,
      themeController: themeController,
      skin: AppSkinRegistry.resolve(skinId),
      apiClient: apiClient,
    ),
  );

  await themeController.initialize();
  unawaited(sessionController.initialize());
}
