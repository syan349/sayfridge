import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/profile_preferences.dart';
import '../repositories/auth_repository.dart';
import '../repositories/profile_preferences_repository.dart';
import '../services/api_exception.dart';

enum AuthStatus { initial, checking, unauthenticated, authenticated, error }

class AuthController extends ChangeNotifier {
  AuthController(
    this._authRepository, [
    this._profileRepository = const ProfilePreferencesRepository(),
  ]);

  final AuthRepository _authRepository;
  final ProfilePreferencesRepository _profileRepository;

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
    String? nickname,
    String avatarAsset = ProfilePreferences.defaultAvatar,
  }) async {
    _startSubmission();

    try {
      final user = await _authRepository.register(
        email: email,
        password: password,
      );
      if (nickname != null) {
        try {
          await _profileRepository.save(
            user.id,
            ProfilePreferences(
              fullName: nickname.trim(),
              avatarAsset: avatarAsset,
            ),
          );
        } catch (_) {
          // The account already exists; do not invite a duplicate registration.
          _errorMessage =
              'Account created. Please sign in. Your nickname and avatar could not be saved on this device; set them in Profile.';
        }
      }

      _status = AuthStatus.unauthenticated;
      return true;
    } catch (error) {
      _errorMessage = _messageFor(error);
      return false;
    } finally {
      _finishSubmission();
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _startSubmission();

    try {
      _user = await _authRepository.login(email: email, password: password);
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

  Future<bool> changePassword({required String currentPassword, required String newPassword}) async {
    if (_isSubmitting) return false;
    _startSubmission();
    try {
      await _authRepository.changePassword(currentPassword: currentPassword, newPassword: newPassword);
      _user = null;
      _status = AuthStatus.unauthenticated;
      return true;
    } catch (error) {
      _errorMessage = error is ApiException && error.statusCode == 0
          ? 'We could not confirm the password change. Please sign in again to check.'
          : _messageFor(error);
      return false;
    } finally { _finishSubmission(); }
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

  void sessionExpired() {
    _user = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = 'Your session has ended. Please sign in again.';
    notifyListeners();
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
