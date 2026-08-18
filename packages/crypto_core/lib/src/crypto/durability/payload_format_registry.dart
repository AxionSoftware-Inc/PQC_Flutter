import 'crypto_durability_models.dart';
import 'package:pqc_engine_sdk/pqc_engine_sdk.dart' as sdk;
import 'v2_protocol_contract.dart';

/// Explicit SDK write profile. A release id and its wire protocol are not the
/// same thing: v2.5 keeps the immutable v2 wire format while v3 writes a new
/// one. The host must select this deliberately, never by decoder presence.
enum PayloadWriteProfile { v2, v25, v3 }

class PayloadFormatRegistry {
  PayloadFormatRegistry({
    List<PayloadFormatDescriptor>? descriptors,
    PayloadWriteProfile? writeProfile,
  }) : writeProfile = writeProfile ?? _environmentProfile,
       _descriptors =
           descriptors ?? _descriptorsFor(writeProfile ?? _environmentProfile);

  final PayloadWriteProfile writeProfile;
  final List<PayloadFormatDescriptor> _descriptors;

  factory PayloadFormatRegistry.forRelease(sdk.PqcProtocolRelease release) {
    return PayloadFormatRegistry(writeProfile: profileForRelease(release));
  }

  static final PayloadWriteProfile _environmentProfile = _profileForRelease(
    const String.fromEnvironment('SDK_RELEASE', defaultValue: ''),
  );

  static PayloadWriteProfile _profileForRelease(String release) {
    final sharedRelease = sdk.PqcProtocolRelease.tryParse(release);
    if (sharedRelease != null) {
      return profileForRelease(sharedRelease);
    }
    return bool.fromEnvironment('V3_WRITER', defaultValue: false)
        ? PayloadWriteProfile.v3
        : PayloadWriteProfile.v2;
  }

  static PayloadWriteProfile profileForRelease(sdk.PqcProtocolRelease release) {
    switch (release.profileId) {
      case 'v2.5':
        return PayloadWriteProfile.v25;
      case 'v3':
        return PayloadWriteProfile.v3;
      default:
        return PayloadWriteProfile.v2;
    }
  }

  sdk.PqcProtocolRelease get protocolRelease => switch (writeProfile) {
    PayloadWriteProfile.v2 => sdk.PqcProtocolRelease.v2,
    PayloadWriteProfile.v25 => sdk.PqcProtocolRelease.v25,
    PayloadWriteProfile.v3 => sdk.PqcProtocolRelease.v3,
  };

  List<String> get supportedProtocolIds =>
      List.unmodifiable(protocolRelease.supportedProtocolIds);

  static List<PayloadFormatDescriptor> _descriptorsFor(
    PayloadWriteProfile writeProfile,
  ) => [
    PayloadFormatDescriptor(
      formatId: 'pqc-private-v2',
      payloadKind: PayloadKind.privateMessage,
      prefix: '${PqcV2ProtocolContract.privatePrefix}:',
      introducedAtVersion: '2.0.0',
      decryptSupported: true,
      writeEnabled:
          writeProfile == PayloadWriteProfile.v2 ||
          writeProfile == PayloadWriteProfile.v25,
    ),
    PayloadFormatDescriptor(
      formatId: 'group-message-v2',
      payloadKind: PayloadKind.groupMessage,
      prefix: '${PqcV2ProtocolContract.groupPrefix}:',
      introducedAtVersion: '2.0.0',
      decryptSupported: true,
      writeEnabled:
          writeProfile == PayloadWriteProfile.v2 ||
          writeProfile == PayloadWriteProfile.v25,
    ),
    PayloadFormatDescriptor(
      formatId: 'group-envelope-pqc-v2',
      payloadKind: PayloadKind.groupEnvelope,
      prefix: '${PqcV2ProtocolContract.groupWrapPrefix}:',
      introducedAtVersion: '2.0.0',
      decryptSupported: true,
      writeEnabled: writeProfile != PayloadWriteProfile.v25,
    ),
    PayloadFormatDescriptor(
      formatId: 'group-envelope-pqc-v2.5',
      payloadKind: PayloadKind.groupEnvelope,
      prefix: '${PqcV2ProtocolContract.groupWrapV25Prefix}:',
      introducedAtVersion: '2.5.0',
      decryptSupported: true,
      writeEnabled: writeProfile == PayloadWriteProfile.v25,
    ),
    PayloadFormatDescriptor(
      formatId: 'pqc-private-v3',
      payloadKind: PayloadKind.privateMessage,
      prefix: 'pqc:v3:',
      introducedAtVersion: '3.0.0',
      decryptSupported: true,
      writeEnabled: writeProfile == PayloadWriteProfile.v3,
    ),
    PayloadFormatDescriptor(
      formatId: 'group-message-v3',
      payloadKind: PayloadKind.groupMessage,
      prefix: 'group:v3:',
      introducedAtVersion: '3.0.0',
      decryptSupported: true,
      writeEnabled: writeProfile == PayloadWriteProfile.v3,
    ),
  ];

  List<PayloadFormatDescriptor> get descriptors =>
      List.unmodifiable(_descriptors);

  PayloadFormatDescriptor? describe(String payload) {
    for (final descriptor in _descriptors) {
      if (descriptor.decryptSupported &&
          payload.startsWith(descriptor.prefix)) {
        return descriptor;
      }
    }
    return null;
  }

  List<PayloadFormatDescriptor> readersFor(PayloadKind kind) => _descriptors
      .where((item) => item.payloadKind == kind && item.decryptSupported)
      .toList(growable: false);

  /// The only formats this client is allowed to create.  Keep this separate
  /// from [describe]: a readable historical format must never become a writer
  /// merely because its decoder is registered.
  List<PayloadFormatDescriptor> writersFor(PayloadKind kind) => _descriptors
      .where((item) => item.payloadKind == kind && item.writeEnabled)
      .toList(growable: false);

  bool supportsWriterPrefix(String prefix) =>
      _descriptors.any((item) => item.prefix == prefix && item.writeEnabled);
}
