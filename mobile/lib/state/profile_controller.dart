import 'package:flutter/foundation.dart';

import '../models/profile_preferences.dart';
import '../repositories/profile_preferences_repository.dart';
import '../services/notification_service.dart';
import 'auth_controller.dart';

class ProfileController extends ChangeNotifier {
  ProfileController(
    this.authController, [
    this._repository = const ProfilePreferencesRepository(),
    NotificationService? notificationService,
  ]) : _notificationService = notificationService {
    authController.addListener(_syncAccount);
    _syncAccount();
    _refreshNotificationPermission();
  }

  final AuthController authController;
  final ProfilePreferencesRepository _repository;
  final NotificationService? _notificationService;
  ProfilePreferences _preferences = const ProfilePreferences();
  String? _userId;
  int _accountVersion = 0;
  bool _disposed = false;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  String? _notificationError;
  bool _isUpdatingNotifications = false;
  NotificationPermissionState _notificationPermission =
      NotificationPermissionState.unknown;

  ProfilePreferences get preferences => _preferences;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;
  String? get notificationError => _notificationError;
  bool get isUpdatingNotifications => _isUpdatingNotifications;
  NotificationPermissionState get notificationPermission =>
      _notificationPermission;
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
      await _syncNotificationSchedule(preferences);
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
    bool? deviceNotifications,
    bool? expiryReminders,
    int? daysBeforeExpiry,
    bool? dailyCheckIn,
    int? notificationHour,
    int? notificationMinute,
  }) => _save(
    _preferences.withReminders(
      deviceNotifications: deviceNotifications,
      expiryReminders: expiryReminders,
      daysBeforeExpiry: daysBeforeExpiry,
      dailyCheckIn: dailyCheckIn,
      notificationHour: notificationHour,
      notificationMinute: notificationMinute,
    ),
  );

  Future<bool> setDeviceNotificationsEnabled(bool enabled) async {
    if (_isSaving || _isLoading || _isUpdatingNotifications) return false;
    final version = _accountVersion;
    if (enabled &&
        _notificationPermission != NotificationPermissionState.enabled) {
      if (!await requestNotificationPermission()) return false;
    }
    if (!_isCurrent(version)) return false;
    return saveReminders(deviceNotifications: enabled);
  }

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
      await _syncNotificationSchedule(preferences);
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

  Future<void> _syncNotificationSchedule(ProfilePreferences preferences) async {
    try {
      await _notificationService?.synchronizeDailyReminder(preferences);
      if (!preferences.deviceNotifications) {
        for (final id in [
          NotificationService.expiredItemsId,
          NotificationService.expiringSoonId,
          NotificationService.dailyCheckInId,
        ]) {
          await _notificationService?.cancel(id);
        }
      }
      _notificationError = null;
    } catch (_) {
      _notificationError =
          'Preferences were saved, but the device reminder could not be scheduled.';
    }
  }

  Future<void> _refreshNotificationPermission() async {
    final notificationService = _notificationService;
    if (notificationService == null) {
      _notificationPermission = NotificationPermissionState.unsupported;
      return;
    }
    try {
      final state = await notificationService.permissionState();
      if (_disposed) return;
      _notificationPermission = state;
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      _notificationPermission = NotificationPermissionState.unsupported;
      notifyListeners();
    }
  }

  Future<bool> requestNotificationPermission() async {
    final notificationService = _notificationService;
    if (notificationService == null) return false;
    if (_isUpdatingNotifications) return false;
    _isUpdatingNotifications = true;
    final version = _accountVersion;
    _notificationError = null;
    notifyListeners();
    try {
      _notificationPermission = await notificationService.requestPermission();
      if (!_isCurrent(version)) return false;
      if (_notificationPermission == NotificationPermissionState.enabled) {
        await notificationService.synchronizeDailyReminder(_preferences);
        return true;
      }
      _notificationError =
          _notificationPermission == NotificationPermissionState.unsupported
          ? 'Notifications are not supported on this device or browser.'
          : 'Notification permission was not granted. You can enable it in device or browser settings.';
      return false;
    } catch (_) {
      _notificationError =
          'Unable to enable notifications. Check device or browser settings and try again.';
      return false;
    } finally {
      if (!_disposed) {
        _isUpdatingNotifications = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    authController.removeListener(_syncAccount);
    super.dispose();
  }
}
