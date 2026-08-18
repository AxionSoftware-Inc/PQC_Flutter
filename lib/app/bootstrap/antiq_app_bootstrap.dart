import 'dart:async';

import 'package:chat_core/chat_core.dart';
import 'package:crypto_core/crypto_core.dart';
import 'package:flutter/widgets.dart';

import '../../core/storage/session_storage.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/account/data/account_repository.dart';
import '../../features/auth/session_controller.dart';
import '../../features/notifications/application/device_notification_service.dart';
import '../../features/rbac/data/rbac_repository.dart';
import '../../features/tasks/data/task_kpi_repository.dart';
import '../../features/crypto/durability/enterprise_recovery_sync_service.dart';
import '../app.dart';
import '../design_system/app_design_system.dart';
import '../modules/antiq_app_module_registry.dart';
import '../theme_controller.dart';

/// The only application composition root. Feature packages never construct
/// crypto/session/network singletons themselves; optional modules are loaded
/// before this stable core is composed.
Future<void> runAntiQApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AntiQAppModuleRegistry().initializeConfiguredModules();
  const skinId = String.fromEnvironment(
    'APP_SKIN',
    defaultValue: AppSkinRegistry.defaultSkinId,
  );

  final themeController = AppThemeController();
  final sessionStorage = SessionStorage();
  final appDatabase = AppDatabase();
  final localDataProtector = LocalDataProtector();
  final apiClient = ApiClient();
  final accountRepository = AccountRepository(apiClient: apiClient);
  final taskKpiRepository = TaskKpiRepository(apiClient: apiClient);
  final rbacRepository = RbacRepository(apiClient: apiClient);
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
  final protocolVersionManager = ProtocolVersionManager();
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
  final deviceNotificationService = DeviceNotificationService(
    apiClient: apiClient,
  );
  await deviceNotificationService.initialize();
  final enableV3Writer =
      protocolVersionManager.registry.writeProfile == PayloadWriteProfile.v3;
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
      codec: SdkV2GroupCipherMessageCodec(
        groupKeyStore: groupKeyStore,
        deviceIdentityService: deviceIdentityService,
        devicePqcKeyService: devicePqcKeyService,
        devicePqcSigningKeyService: devicePqcSigningKeyService,
      ),
    ),
    PqcPrivateChatAlgorithm(
      deviceIdentityService: deviceIdentityService,
      devicePqcKeyService: devicePqcKeyService,
      devicePqcSigningKeyService: devicePqcSigningKeyService,
      keyMaterialRegistry: keyMaterialRegistry,
      codec: SdkV2PrivateMessageCodec(
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
    protocolVersionManager: protocolVersionManager,
  );
  final cryptoCoreFacade = CryptoCoreFacade(
    cipherService: chatCipherService,
    groupKeyStore: groupKeyStore,
    keyMaterialRegistry: keyMaterialRegistry,
    backupService: CryptoBackupService(
      keyMaterialRegistry: keyMaterialRegistry,
    ),
    protocolVersionManager: protocolVersionManager,
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
    attachmentTransferFacade: AttachmentTransferFacade(
      remoteDataSource: remoteDataSource,
    ),
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
        await deviceNotificationService.stop();
        return;
      }
      await cryptoCoreFacade.activateAccount('${sessionUser.accountId}');
      await enterpriseRecoverySyncService.restoreIfAvailable();
      await cryptoCoreFacade.initialize();
      try {
        await enterpriseRecoverySyncService.publishInBackground();
      } catch (_) {
        // Sending and the next lifecycle event retry recovery publication.
      }
      await chatRealtimeService.connect(
        token: sessionUser.token,
        workspaceId: '${sessionUser.activeWorkspaceId}',
        deviceId: sessionUser.deviceId,
      );
      await deviceNotificationService.start(
        currentUserId: sessionUser.id,
        accountId: sessionUser.accountId,
        workspaceId: sessionUser.activeWorkspaceId,
        realtimeEvents: chatFacade.realtimeEvents,
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
      accountRepository: accountRepository,
      taskKpiRepository: taskKpiRepository,
      rbacRepository: rbacRepository,
      database: appDatabase,
    ),
  );
  await themeController.initialize();
  unawaited(sessionController.initialize());
}
