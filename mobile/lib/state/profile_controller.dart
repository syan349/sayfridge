import 'package:flutter/foundation.dart';

import '../models/profile_preferences.dart';
import '../repositories/profile_preferences_repository.dart';
import 'auth_controller.dart';

class ProfileController extends ChangeNotifier {
  ProfileController(
    this.authController, [
    this._repository = const ProfilePreferencesRepository(),
  ]) {
    authController.addListener(_syncAccount);
    _syncAccount();
  }

  final AuthController authController;
  final ProfilePreferencesRepository _repository;
  ProfilePreferences _preferences = const ProfilePreferences();
  String? _userId;
  int _accountVersion = 0;
  bool _disposed = false;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  ProfilePreferences get preferences => _preferences;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;
  String get displayName => _preferences.fullName.isNotEmpty
      ? _preferences.fullName
      : authController.user?.email.split('@').first ?? 'Guest';

  void _syncAccount() {
    final nextId = authController.user?.id;
    if (nextId == _userId) return;
    _userId = nextId;
    _accountVersion++;
    _preferences = const ProfilePreferences();
    _error = null;
    _isSaving = false;
    _isLoading = nextId != null;
    notifyListeners();
    if (nextId != null) _load(nextId, _accountVersion);
  }

  Future<void> reload() async {
    final userId = _userId;
    if (userId == null || _isLoading || _isSaving) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    await _load(userId, _accountVersion);
  }

  Future<void> _load(String userId, int version) async {
    try {
      final preferences = await _repository.read(userId);
      if (!_isCurrent(version)) return;
      _preferences = preferences;
    } catch (_) {
      if (!_isCurrent(version)) return;
      _error = 'Unable to load your saved preferences. Please try again.';
    }
    if (!_isCurrent(version)) return;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> saveIdentity({
    required String fullName,
    required String avatarAsset,
    Uint8List? avatarBytes,
  }) => _save(
    _preferences.withIdentity(
      fullName: fullName.trim(),
      avatarAsset: avatarAsset,
      avatarBytes: avatarBytes,
    ),
  );

  Future<bool> saveReminders({
    bool? expiryReminders,
    int? daysBeforeExpiry,
    bool? dailyCheckIn,
    int? notificationHour,
    int? notificationMinute,
  }) => _save(
    _preferences.withReminders(
      expiryReminders: expiryReminders,
      daysBeforeExpiry: daysBeforeExpiry,
      dailyCheckIn: dailyCheckIn,
      notificationHour: notificationHour,
      notificationMinute: notificationMinute,
    ),
  );

  Future<bool> _save(ProfilePreferences preferences) async {
    final userId = _userId;
    if (userId == null || _isLoading || _isSaving) return false;
    final version = _accountVersion;
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.save(userId, preferences);
      if (!_isCurrent(version)) return false;
      _preferences = preferences;
      return true;
    } catch (_) {
      if (_isCurrent(version)) {
        _error = 'Unable to save your changes. Please try again.';
      }
      return false;
    } finally {
      if (_isCurrent(version)) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int version) => !_disposed && version == _accountVersion;

  @override
  void dispose() {
    _disposed = true;
    authController.removeListener(_syncAccount);
    super.dispose();
  }
}
