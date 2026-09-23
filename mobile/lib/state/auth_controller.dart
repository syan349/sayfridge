import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import '../services/api_exception.dart';

enum AuthStatus {
  initial,
  checking,
  unauthenticated,
  authenticated,
  error,
}

class AuthController extends ChangeNotifier {
  AuthController(this._authRepository);

  final AuthRepository _authRepository;

  AuthStatus _status = AuthStatus.initial;
  AppUser? _user;
  String? _errorMessage;
  bool _isSubmitting = false;

  AuthStatus get status => _status;

  AppUser? get user => _user;

  String? get errorMessage => _errorMessage;

  bool get isSubmitting => _isSubmitting;

  bool get isAuthenticated => _status == AuthStatus.authenticated;

  Future<void> initialize() async {
    _status = AuthStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authRepository.restoreSession();
      _status = _user == null
          ? AuthStatus.unauthenticated
          : AuthStatus.authenticated;
    } catch (error) {
      _user = null;
      _status = AuthStatus.error;
      _errorMessage = _messageFor(error);
    }

    notifyListeners();
  }

  Future<bool> register({
    required String email,
    required String password,
  }) async {
    _startSubmission();

    try {
      await _authRepository.register(
        email: email,
        password: password,
      );

      _status = AuthStatus.unauthenticated;
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error);
      return false;
    } finally {
      _finishSubmission();
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _startSubmission();

    try {
      _user = await _authRepository.login(
        email: email,
        password: password,
      );
      _status = AuthStatus.authenticated;
      return true;
    } catch (error) {
      _user = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = _messageFor(error);
      return false;
    } finally {
      _finishSubmission();
    }
  }

  Future<bool> logout() async {
    _startSubmission();

    try {
      await _authRepository.logout();
      _user = null;
      _status = AuthStatus.unauthenticated;
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error);
      return false;
    } finally {
      _finishSubmission();
    }
  }

  void clearError() {
    if (_errorMessage == null) return;

    _errorMessage = null;
    notifyListeners();
  }

  void _startSubmission() {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
  }

  void _finishSubmission() {
    _isSubmitting = false;
    notifyListeners();
  }

  String _messageFor(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 0) {
        return 'Unable to connect to the server. Please try again.';
      }

      return error.message;
    }

    return 'Something went wrong. Please try again.';
  }
}