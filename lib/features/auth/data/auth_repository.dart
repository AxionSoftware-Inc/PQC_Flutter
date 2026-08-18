import '../../../core/device/device_identity_service.dart';
import '../../../core/config/api_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/device/device_state_manager.dart';
import '../../../core/device/device_key_service.dart';
import '../../../core/device/device_pqc_key_service.dart';
import '../../../core/device/device_pqc_signing_key_service.dart';
import '../../../core/device/device_security_state_service.dart';
import '../../../core/models/organization_context.dart';
import '../../../core/models/session_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/session_storage.dart';
import '../../chat/data/outbox_store.dart';
import '../../../core/models/chat_message.dart';
import '../../crypto/outbound_message_cache.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:crypto_core/crypto_core.dart' show PayloadFormatRegistry;

// ignore_for_file: prefer_initializing_formals

part 'auth_google_actions.dart';
part 'auth_session_actions.dart';
part 'auth_device_actions.dart';

const _unsupportedPqcServerMessage =
    'Connected server is running an old backend and does not store PQC device keys yet. Update/deploy the latest backend or switch API_BASE_URL to the updated server.';

abstract class _AuthRepositoryBase {
  _AuthRepositoryBase({
    required this.apiClient,
    required this.sessionStorage,
    required this.deviceIdentityService,
    required this.deviceKeyService,
    required this.devicePqcKeyService,
    required this.devicePqcSigningKeyService,
    required this.deviceSecurityStateService,
    required this.deviceStateManager,
    this.appDatabase,
    OutboundMessageCache? outboundMessageCache,
    OutboxStore? outboxStore,
  }) : _outboundMessageCache = outboundMessageCache,
       _outboxStore = outboxStore;

  final ApiClient apiClient;
  final SessionStorage sessionStorage;
  final DeviceIdentityService deviceIdentityService;
  final DeviceKeyService deviceKeyService;
  final DevicePqcKeyService devicePqcKeyService;
  final DevicePqcSigningKeyService devicePqcSigningKeyService;
  final DeviceSecurityStateService deviceSecurityStateService;
  final DeviceStateManager deviceStateManager;
  final AppDatabase? appDatabase;
  final OutboundMessageCache? _outboundMessageCache;
  final OutboxStore? _outboxStore;
  bool _googleInitialized = false;
  _PqcRegistrationPayload _buildPqcRegistrationPayloadFromState(
    DeviceProfileState deviceState,
  ) {
    final pqcKeyMaterial = deviceState.pqcKeyMaterial;
    if (pqcKeyMaterial == null) {
      return const _PqcRegistrationPayload(publicKey: '', algorithm: '');
    }
    return _PqcRegistrationPayload(
      publicKey: pqcKeyMaterial.publicKey,
      algorithm: pqcKeyMaterial.algorithm,
    );
  }

  List<String> _supportedProtocolIds() =>
      PayloadFormatRegistry().supportedProtocolIds;

  Future<DeviceProfileState> _prepareDeviceState() async {
    final deviceState = await deviceStateManager.resolveCurrentDeviceProfile();
    if (deviceState.didRotateInstallation) {
      await _outboundMessageCache?.clearAll();
      final queuedMessages = await _outboxStore?.readAll() ?? const [];
      for (final item in queuedMessages) {
        await _outboxStore?.upsert(
          item.copyWith(
            deliveryState: MessageDeliveryState.failedPermanent,
            failureReason: 'outbox_payload_invalid_after_rotation',
          ),
        );
      }
    }
    return deviceState;
  }

  List<OrganizationSummary> _parseOrganizations(Map<String, dynamic> response) {
    return (response['organizations'] as List<dynamic>? ?? const [])
        .map(
          (item) => OrganizationSummary.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  void _assertServerAcceptedPqcKeys({
    required Map<String, dynamic> response,
    required String expectedDeviceId,
    required String expectedPqcPublicKey,
    required String expectedSigningPublicKey,
  }) {
    if (expectedPqcPublicKey.isEmpty || expectedSigningPublicKey.isEmpty) {
      return;
    }

    final user = response['user'] as Map<String, dynamic>?;
    if (user != null) {
      final devices = user['devices'] as List<dynamic>? ?? const [];
      for (final item in devices) {
        final device = item as Map<String, dynamic>;
        if ((device['device_id'] as String? ?? '') != expectedDeviceId) {
          continue;
        }
        final returnedPqcPublicKey = device['pqc_public_key'] as String? ?? '';
        final returnedSigningPublicKey =
            device['pqc_signing_public_key'] as String? ?? '';
        if (returnedPqcPublicKey == expectedPqcPublicKey &&
            returnedSigningPublicKey == expectedSigningPublicKey) {
          return;
        }
        throw ApiException(
          _unsupportedPqcServerMessage,
          code: 'server_missing_pqc_device_keys',
        );
      }
    }

    final returnedPqcPublicKey = response['pqc_public_key'] as String? ?? '';
    final returnedSigningPublicKey =
        response['pqc_signing_public_key'] as String? ?? '';
    if (returnedPqcPublicKey == expectedPqcPublicKey &&
        returnedSigningPublicKey == expectedSigningPublicKey) {
      return;
    }

    throw ApiException(
      _unsupportedPqcServerMessage,
      code: 'server_missing_pqc_device_keys',
    );
  }
}

class AuthRepository extends _AuthRepositoryBase
    with _AuthGoogleActions, _AuthSessionActions, _AuthDeviceActions {
  AuthRepository({
    required super.apiClient,
    required super.sessionStorage,
    required super.deviceIdentityService,
    required super.deviceKeyService,
    required super.devicePqcKeyService,
    required super.devicePqcSigningKeyService,
    required super.deviceSecurityStateService,
    required super.deviceStateManager,
    super.appDatabase,
    super.outboundMessageCache,
    super.outboxStore,
  });
}

class _PqcRegistrationPayload {
  const _PqcRegistrationPayload({
    required this.publicKey,
    required this.algorithm,
  });

  final String publicKey;
  final String algorithm;
}
