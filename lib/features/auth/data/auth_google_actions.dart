part of 'auth_repository.dart';

mixin _AuthGoogleActions on _AuthRepositoryBase {
  Future<SessionUser> _sessionFromResponse(
    Map<String, dynamic> response,
    String fallbackDeviceId,
  );

  Future<SessionUser> loginWithGoogle() async {
    try {
      return await _loginWithGoogleInternal();
    } on GoogleSignInException catch (error) {
      throw ApiException(
        _googleSignInErrorMessage(error),
        code: 'google_sign_in_${error.code.name}',
      );
    }
  }

  Future<SessionUser> _loginWithGoogleInternal() async {
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize(
        serverClientId: ApiConfig.googleWebClientId,
      );
      _googleInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw ApiException(
        'Google did not return an ID token.',
        code: 'google_token_missing',
      );
    }

    final deviceState = await _prepareDeviceState();
    final identity = deviceState.deviceIdentity;
    final pqc = _buildPqcRegistrationPayloadFromState(deviceState);
    final response = await apiClient.post('/auth/google', {
      'id_token': idToken,
      'device_id': identity.id,
      'device_name': identity.deviceName,
      'platform': identity.platform,
      'identity_public_key': deviceState.identityKeyMaterial.publicKey,
      'key_algorithm': deviceState.identityKeyMaterial.algorithm,
      'pqc_public_key': pqc.publicKey,
      'pqc_algorithm': pqc.algorithm,
      'pqc_signing_public_key': deviceState.pqcSigningKeyMaterial.publicKey,
      'pqc_signing_algorithm': deviceState.pqcSigningKeyMaterial.algorithm,
      'supported_protocols': _supportedProtocolIds(),
    });
    if (response is! Map<String, dynamic>) {
      throw ApiException(
        'Google login response is invalid.',
        code: 'google_response_invalid',
      );
    }
    apiClient.setRecoveryGrant(response['recovery_grant'] as String?);
    return _sessionFromResponse(response, identity.id);
  }

  String _googleSignInErrorMessage(GoogleSignInException error) {
    final detail = error.description?.trim();
    final suffix = detail == null || detail.isEmpty ? '' : ' ($detail)';
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled =>
        'Google orqali kirish bekor qilindi.',
      GoogleSignInExceptionCode.interrupted =>
        'Google orqali kirish uzildi. Internetni tekshirib, qayta urinib ko‘ring.',
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Google login sozlamasi mos emas. Android package com.axion.pqc va release SHA-1 Google Cloud’da ro‘yxatdan o‘tganini tekshirish kerak.$suffix',
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Qurilmadagi Google Play Services sozlamasi ishlamadi. Google ilovalari va Play Services’ni yangilab, qayta urinib ko‘ring.$suffix',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Google login oynasini ochib bo‘lmadi. Ilovani yopib qayta oching.$suffix',
      GoogleSignInExceptionCode.userMismatch =>
        'Google akkaunt sessiyasi mos kelmadi. Google login oynasida akkauntni qayta tanlang.$suffix',
      GoogleSignInExceptionCode.unknownError =>
        'Google orqali kirib bo‘lmadi. Qayta urinib ko‘ring.$suffix',
    };
  }
}
