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
    _error = null;
    notifyListeners();
    try {
      _sessionUser = await authRepository.restoreSession();
      await _notifySessionChanged(_sessionUser);
    } catch (error) {
      _sessionUser = null;
      _error = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username) async {
    _setLoading(true);
    _error = null;

    try {
      _sessionUser = await authRepository.login(username.trim());
      await _notifySessionChanged(_sessionUser);
      return true;
    } catch (error) {
      _error = error.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> loginWithGoogle() async {
    _setLoading(true);
    _error = null;
    try {
      _sessionUser = await authRepository.loginWithGoogle();
      await _notifySessionChanged(_sessionUser);
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
      await _notifySessionChanged(_sessionUser);
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
    await _notifySessionChanged(null);
    _setLoading(false);
  }

  Future<void> logoutAndForgetDevice() async {
    _setLoading(true);
    await authRepository.logout(
      clearRememberedIdentity: true,
      preserveLocalHistory: false,
    );
    _sessionUser = null;
    _error = null;
    await _notifySessionChanged(null);
    _setLoading(false);
  }

  Future<void> invalidateSession() async {
    await authRepository.logout(clearRememberedIdentity: false);
    _sessionUser = null;
    _error = 'Session expired. Please log in again.';
    await _notifySessionChanged(null);
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
      await _notifySessionChanged(_sessionUser);
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

  Future<void> _notifySessionChanged(SessionUser? sessionUser) async {
    final callback = onSessionChanged;
    if (callback == null) {
      return;
    }
    try {
      await callback(sessionUser).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Realtime/session side effects should not block the whole app shell.
    }
  }
}
