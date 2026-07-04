import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'core/device/device_identity_service.dart';
import 'core/device/device_key_service.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_storage.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/session_controller.dart';
import 'features/chat/data/chat_remote_data_source.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/crypto/group_key_store.dart';
import 'features/crypto/message_codec.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sessionStorage = SessionStorage();
  final apiClient = ApiClient();
  final deviceIdentityService = DeviceIdentityService();
  final deviceKeyService = DeviceKeyService();
  final remoteDataSource = ChatRemoteDataSource(apiClient: apiClient);
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
  );
  final sessionController = SessionController(authRepository: authRepository);
  final chatRepository = ChatRepository(
    remoteDataSource: remoteDataSource,
    composerService: HybridMessageComposerService(
      deviceKeyService: deviceKeyService,
      groupKeyStore: groupKeyStore,
    ),
    decoderService: HybridMessageDecoderService(
      deviceKeyService: deviceKeyService,
      groupKeyStore: groupKeyStore,
    ),
  );

  await sessionController.initialize();

  runApp(
    PqcChatApp(
      sessionController: sessionController,
      chatRepository: chatRepository,
    ),
  );
}
