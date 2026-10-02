import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/profile_preferences.dart';

enum NotificationPermissionState { unsupported, unknown, denied, enabled }

class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int dailyReminderId = 7000;
  static const int expiredItemsId = 7001;
  static const int expiringSoonId = 7002;
  static const int dailyCheckInId = 7003;

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _selectedPayloads =
      StreamController<String>.broadcast();
  bool _initialized = false;
  bool _timeZoneInitialized = false;

  Stream<String> get selectedPayloads => _selectedPayloads.stream;

  bool get isSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        web: WebInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _selectedPayloads.add(payload);
        }
      },
    );
    _initialized = true;
  }

  Future<NotificationPermissionState> permissionState() async {
    if (!isSupported) return NotificationPermissionState.unsupported;
    await initialize();
    if (kIsWeb) {
      final web = _plugin
          .resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin
          >();
      if (web == null || !WebFlutterLocalNotificationsPlugin.isSupported) {
        return NotificationPermissionState.unsupported;
      }
      return switch (web.permissionStatus) {
        WebNotificationPermission.granted =>
          NotificationPermissionState.enabled,
        WebNotificationPermission.denied => NotificationPermissionState.denied,
        _ => NotificationPermissionState.unknown,
      };
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final enabled = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      return enabled == true
          ? NotificationPermissionState.enabled
          : NotificationPermissionState.unknown;
    }
    final options = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    return options?.isEnabled == true
        ? NotificationPermissionState.enabled
        : NotificationPermissionState.unknown;
  }

  Future<NotificationPermissionState> requestPermission() async {
    if (!isSupported) return NotificationPermissionState.unsupported;
    await initialize();
    bool? granted;
    if (kIsWeb) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    return granted == true
        ? NotificationPermissionState.enabled
        : NotificationPermissionState.denied;
  }

  Future<void> synchronizeDailyReminder(ProfilePreferences preferences) async {
    if (!isSupported || kIsWeb) return;
    await initialize();
    await _plugin.cancel(id: dailyReminderId);
    if (!preferences.deviceNotifications ||
        (!preferences.expiryReminders && !preferences.dailyCheckIn)) {
      return;
    }
    if (await permissionState() != NotificationPermissionState.enabled) return;

    await _initializeTimeZone();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      preferences.notificationHour,
      preferences.notificationMinute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    final body = switch ((
      preferences.expiryReminders,
      preferences.dailyCheckIn,
    )) {
      (true, true) =>
        'Check your inventory and items expiring within ${preferences.daysBeforeExpiry} days.',
      (true, false) =>
        'Check items expiring within ${preferences.daysBeforeExpiry} days.',
      _ => 'Review your storage spaces and inventory.',
    };
    await _plugin.zonedSchedule(
      id: dailyReminderId,
      title: 'SayFridge reminder',
      body: body,
      payload: 'daily',
      scheduledDate: scheduled,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required String payload,
    bool processAction = false,
  }) async {
    if (!isSupported) return;
    await initialize();
    if (await permissionState() != NotificationPermissionState.enabled) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: _details(processAction: processAction),
    );
  }

  Future<void> cancel(int id) async {
    if (!isSupported) return;
    await initialize();
    await _plugin.cancel(id: id);
  }

  NotificationDetails _details({bool processAction = false}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          'sayfridge_reminders',
          'Inventory reminders',
          channelDescription: 'Expiry and inventory reminders from SayFridge',
          importance: Importance.high,
          priority: Priority.high,
          actions: processAction
              ? const [
                  AndroidNotificationAction(
                    'process_now',
                    'Process now',
                    showsUserInterface: true,
                  ),
                ]
              : null,
        ),
        iOS: const DarwinNotificationDetails(),
        web: WebNotificationDetails(
          requireInteraction: processAction,
          actions: processAction
              ? const [
                  WebNotificationAction(
                    action: 'process_now',
                    title: 'Process now',
                  ),
                ]
              : const [],
        ),
      );

  Future<void> _initializeTimeZone() async {
    if (_timeZoneInitialized) return;
    tz.initializeTimeZones();
    final local = await FlutterTimezone.getLocalTimezone();
    try {
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } on tz.LocationNotFoundException {
      tz.setLocalLocation(tz.UTC);
    }
    _timeZoneInitialized = true;
  }

  void dispose() {
    _selectedPayloads.close();
  }
}
