import 'package:flutter/foundation.dart';

import '../../core/models/session_user.dart';
import 'data/auth_repository.dart';

class SessionController extends ChangeNotifier {
  SessionController({required this.authRepository, this.onSessionChanged});

  final AuthRepository authRepository;
  final Future<void> Function(SessionUser? sessionUser)? onSessionChanged;

  SessionUser? _sessionUser;
  bool _isLoading = true;
  String? _error;

  SessionUser? get sessionUser => _sessionUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _sessionUser != null;
  String? get error => _error;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    _sessionUser = await authRepository.restoreSession();
    await onSessionChanged?.call(_sessionUser);
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String username) async {
    _setLoading(true);
    _error = null;

    try {
      _sessionUser = await authRepository.login(username.trim());
      await onSessionChanged?.call(_sessionUser);
      return true;
    } catch (error) {
      _error = error.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> bootstrapLogin() async {
    _setLoading(true);
    _error = null;

    try {
      _sessionUser = await authRepository.bootstrapLogin();
      await onSessionChanged?.call(_sessionUser);
      return true;
    } catch (error) {
      _error = error.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<String> suggestedBootstrapName() {
    return authRepository.suggestedBootstrapName();
  }

  Future<void> logout() async {
    _setLoading(true);
    await authRepository.logout();
    _sessionUser = null;
    _error = null;
    await onSessionChanged?.call(null);
    _setLoading(false);
  }

  Future<void> invalidateSession() async {
    await authRepository.logout(clearRememberedIdentity: false);
    _sessionUser = null;
    _error = 'Session expired. Please log in again.';
    await onSessionChanged?.call(null);
    notifyListeners();
  }

  Future<void> switchWorkspace(int workspaceId) async {
    final sessionUser = _sessionUser;
    if (sessionUser == null || sessionUser.activeWorkspaceId == workspaceId) {
      return;
    }
    _setLoading(true);
    _error = null;
    try {
      _sessionUser = await authRepository.switchWorkspace(
        sessionUser,
        workspaceId,
      );
      await onSessionChanged?.call(_sessionUser);
    } catch (error) {
      _error = error.toString();
    } finally {
      _setLoading(false);
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
