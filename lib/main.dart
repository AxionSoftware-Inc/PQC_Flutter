import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'core/device/device_identity_service.dart';
import 'core/device/device_key_service.dart';
import 'core/device/device_pqc_key_service.dart';
import 'core/device/device_pqc_signing_key_service.dart';
import 'core/device/device_prekey_service.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_storage.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/session_controller.dart';
import 'features/chat/data/chat_remote_data_source.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/chat/data/outbox_store.dart';
import 'features/chat/data/private_conversation_security_coordinator.dart';
import 'features/crypto/chat_cipher_algorithms.dart';
import 'features/crypto/chat_cipher_service.dart';
import 'features/crypto/group_key_store.dart';
import 'features/crypto/outbound_message_cache.dart';
import 'features/crypto/private_session_store.dart';
import 'features/security/key_verification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sessionStorage = SessionStorage();
  final apiClient = ApiClient();
  final deviceIdentityService = DeviceIdentityService();
  final deviceKeyService = DeviceKeyService();
  final devicePqcKeyService = DevicePqcKeyService();
  final devicePqcSigningKeyService = DevicePqcSigningKeyService();
  final devicePreKeyService = DevicePreKeyService();
  final privateSessionStore = PrivateSessionStore();
  final outboundMessageCache = OutboundMessageCache();
  final remoteDataSource = ChatRemoteDataSource(apiClient: apiClient);
  final outboxStore = OutboxStore();
  final keyVerificationService = KeyVerificationService();
  final groupKeyStore = GroupKeyStore(
    deviceIdentityService: deviceIdentityService,
    deviceKeyService: deviceKeyService,
    remoteDataSource: remoteDataSource,
  );
  final authRepository = AuthRepository(
    apiClient: apiClient,
    sessionStorage: sessionStorage,
    deviceIdentityService: deviceIdentityService,
    deviceKeyService: deviceKeyService,
    devicePqcKeyService: devicePqcKeyService,
    devicePqcSigningKeyService: devicePqcSigningKeyService,
    devicePreKeyService: devicePreKeyService,
    outboundMessageCache: outboundMessageCache,
    outboxStore: outboxStore,
  );
  final sessionController = SessionController(authRepository: authRepository);
  final chatCipherService = RoutedChatCipherService(
    algorithms: [
      GroupChatCipherAlgorithm(groupKeyStore: groupKeyStore),
      StablePrivateChatAlgorithm(),
      LegacyPrivateTransportDecryptAlgorithm(
        deviceIdentityService: deviceIdentityService,
        deviceKeyService: deviceKeyService,
        devicePqcKeyService: devicePqcKeyService,
        devicePqcSigningKeyService: devicePqcSigningKeyService,
        devicePreKeyService: devicePreKeyService,
        privateSessionStore: privateSessionStore,
      ),
    ],
    outboundMessageCache: outboundMessageCache,
  );
  final privateConversationSecurityCoordinator =
      PrivateConversationSecurityCoordinator(
        keyVerificationService: keyVerificationService,
      );
  final chatRepository = ChatRepository(
    remoteDataSource: remoteDataSource,
    cipherService: chatCipherService,
    keyVerificationService: keyVerificationService,
    privateConversationSecurityCoordinator:
        privateConversationSecurityCoordinator,
    outboxStore: outboxStore,
  );

  await sessionController.initialize();

  runApp(
    PqcChatApp(
      sessionController: sessionController,
      chatRepository: chatRepository,
    ),
  );
}
