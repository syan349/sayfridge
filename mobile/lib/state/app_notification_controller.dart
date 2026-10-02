import 'dart:async';

import 'package:flutter/foundation.dart';

import '../repositories/notification_state_repository.dart';
import '../services/notification_service.dart';
import 'auth_controller.dart';
import 'expiry_summary_controller.dart';
import 'profile_controller.dart';

enum AppNotificationType { expired, expiring, daily }

class AppNotification {
  const AppNotification({
    required this.type,
    required this.title,
    required this.message,
    required this.processable,
  });

  final AppNotificationType type;
  final String title;
  final String message;
  final bool processable;
}

class AppNotificationController extends ChangeNotifier {
  AppNotificationController({
    required this.authController,
    required this.profileController,
    required this.expiryController,
    required this.service,
    this.repository = const NotificationStateRepository(),
  }) {
    authController.addListener(_queueEvaluate);
    profileController.addListener(_queueEvaluate);
    expiryController.addListener(_queueEvaluate);
    _payloadSubscription = service.selectedPayloads.listen((payload) {
      if (payload == 'expired') onProcessExpired?.call();
      if (payload == 'daily') onDailyCheckIn?.call();
    });
    _queueEvaluate();
  }

  final AuthController authController;
  final ProfileController profileController;
  final ExpirySummaryController expiryController;
  final NotificationService service;
  final NotificationStateRepository repository;
  late final StreamSubscription<String> _payloadSubscription;
  final Set<AppNotificationType> _shownThisSession = {};
  List<AppNotification> _notifications = const [];
  String? _activeUserId;
  int _evaluation = 0;
  bool _disposed = false;

  VoidCallback? onProcessExpired;
  VoidCallback? onDailyCheckIn;
  List<AppNotification> get notifications => _notifications;

  void _queueEvaluate() {
    unawaited(_evaluate());
  }

  Future<void> _evaluate() async {
    final userId = authController.isAuthenticated
        ? authController.user?.id
        : null;
    if (userId != _activeUserId) {
      _activeUserId = userId;
      _shownThisSession.clear();
      ++_evaluation;
    }
    if (userId == null || profileController.isLoading) {
      _setNotifications(const []);
      return;
    }
    if (expiryController.status != ExpirySummaryLoadStatus.loaded &&
        expiryController.status != ExpirySummaryLoadStatus.empty) {
      return;
    }
    final run = ++_evaluation;
    final today = _dateKey(DateTime.now());
    final preferences = profileController.preferences;
    if (expiryController.daysBefore != preferences.daysBeforeExpiry) {
      await expiryController.loadSummary(
        asOf: DateTime.now(),
        daysBefore: preferences.daysBeforeExpiry,
      );
      return;
    }
    final candidates = <AppNotification>[];
    final counts = expiryController.counts;
    if (preferences.expiryReminders && counts.overdue > 0) {
      candidates.add(
        AppNotification(
          type: AppNotificationType.expired,
          title: 'Expired items',
          message:
              '${counts.overdue} ${counts.overdue == 1 ? 'item has' : 'items have'} expired and should be reviewed.',
          processable: true,
        ),
      );
    }
    final expiring = counts.today + counts.upcoming;
    if (preferences.expiryReminders && expiring > 0) {
      candidates.add(
        AppNotification(
          type: AppNotificationType.expiring,
          title: 'Items expiring soon',
          message:
              '$expiring ${expiring == 1 ? 'item is' : 'items are'} due within ${preferences.daysBeforeExpiry} days.',
          processable: false,
        ),
      );
    }
    if (preferences.dailyCheckIn) {
      candidates.add(
        const AppNotification(
          type: AppNotificationType.daily,
          title: 'Daily inventory check-in',
          message: 'Review your storage spaces and update anything you used.',
          processable: false,
        ),
      );
    }

    final unread = <AppNotification>[];
    for (final notification in candidates) {
      final readDate = await repository.readDate(
        userId,
        notification.type.name,
      );
      if (run != _evaluation || _disposed) return;
      if (readDate != today) unread.add(notification);
    }
    _setNotifications(unread);
    if (!profileController.preferences.deviceNotifications) return;
    if (profileController.notificationPermission !=
        NotificationPermissionState.enabled) {
      return;
    }
    for (final notification in unread) {
      if (run != _evaluation ||
          _disposed ||
          !profileController.preferences.deviceNotifications) {
        return;
      }
      if (!_shownThisSession.add(notification.type)) continue;
      await service.showNow(
        id: switch (notification.type) {
          AppNotificationType.expired => NotificationService.expiredItemsId,
          AppNotificationType.expiring => NotificationService.expiringSoonId,
          AppNotificationType.daily => NotificationService.dailyCheckInId,
        },
        title: notification.title,
        body: notification.message,
        payload: notification.type.name,
        processAction: notification.processable,
      );
    }
  }

  Future<void> markRead(AppNotificationType type) async {
    final userId = authController.user?.id;
    if (userId == null) return;
    await repository.saveDate(userId, type.name, _dateKey(DateTime.now()));
    await service.cancel(switch (type) {
      AppNotificationType.expired => NotificationService.expiredItemsId,
      AppNotificationType.expiring => NotificationService.expiringSoonId,
      AppNotificationType.daily => NotificationService.dailyCheckInId,
    });
    _notifications = _notifications
        .where((notification) => notification.type != type)
        .toList(growable: false);
    notifyListeners();
  }

  void _setNotifications(List<AppNotification> value) {
    if (listEquals(_notifications, value)) return;
    _notifications = List.unmodifiable(value);
    if (!_disposed) notifyListeners();
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _disposed = true;
    ++_evaluation;
    authController.removeListener(_queueEvaluate);
    profileController.removeListener(_queueEvaluate);
    expiryController.removeListener(_queueEvaluate);
    _payloadSubscription.cancel();
    super.dispose();
  }
}
