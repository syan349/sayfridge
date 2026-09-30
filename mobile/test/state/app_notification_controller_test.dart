import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sayfridge/models/app_user.dart';
import 'package:sayfridge/models/profile_preferences.dart';
import 'package:sayfridge/repositories/auth_repository.dart';
import 'package:sayfridge/repositories/inventory_repository.dart';
import 'package:sayfridge/repositories/notification_state_repository.dart';
import 'package:sayfridge/repositories/profile_preferences_repository.dart';
import 'package:sayfridge/services/api_client.dart';
import 'package:sayfridge/services/inventory_api_service.dart';
import 'package:sayfridge/services/notification_service.dart';
import 'package:sayfridge/state/app_notification_controller.dart';
import 'package:sayfridge/state/auth_controller.dart';
import 'package:sayfridge/state/expiry_summary_controller.dart';
import 'package:sayfridge/state/inventory_controller.dart';
import 'package:sayfridge/state/profile_controller.dart';
import 'package:sayfridge/screens/home_screen.dart';
import 'package:sayfridge/theme/app_theme.dart';

import '../support/integration_fixtures.dart';

void main() {
  testWidgets(
    'home opens notifications separately and updates the bell after reading',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = AuthController(_Accounts());
      await auth.initialize();
      final profile = ProfileController(auth, _Preferences());
      await tester.runAsync(() => pumpEventQueue());
      final api = ApiClient(
        client: MockClient(
          (request) async => jsonResponse(
            request.url.path.endsWith('/expiry-summary')
                ? {
                    'counts': {'overdue': 1, 'today': 1, 'upcoming': 0},
                    'items': <Object>[],
                    'total': 2,
                    'page': 1,
                    'page_size': 20,
                  }
                : {'items': <Object>[], 'total': 0, 'page': 1, 'page_size': 20},
          ),
        ),
      );
      final repository = InventoryRepository(
        InventoryApiService(api),
        MemoryTokens(),
      );
      final expiry = ExpirySummaryController(repository);
      final inventory = InventoryController(repository);
      final service = _NotificationService();
      final notifications = AppNotificationController(
        authController: auth,
        profileController: profile,
        expiryController: expiry,
        service: service,
        repository: _NotificationState(),
      );
      addTearDown(() {
        notifications.dispose();
        expiry.dispose();
        inventory.dispose();
        profile.dispose();
        auth.dispose();
        api.close();
        service.dispose();
      });
      await tester.runAsync(() async {
        await expiry.loadSummary(asOf: DateUtils.dateOnly(DateTime.now()));
        await inventory.loadInventory();
        await pumpEventQueue();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(
            onAssistantTap: () {},
            notificationController: notifications,
            expirySummaryController: expiry,
            inventoryController: inventory,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Home header must fit');
      expect(find.text('Expired items'), findsNothing);
      expect(find.text('Notifications'), findsNothing);
      await tester.tap(find.byTooltip('Notifications, unread'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Expired items'), findsOneWidget);
      expect(find.text('Items expiring soon'), findsOneWidget);
      expect(find.text('Daily inventory check-in'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Notification cards must fit',
      );

      await tester.runAsync(() async {
        await tester.tap(find.text('Process now'));
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      expect(expiry.bucket, 'overdue');
      expect(find.text('Expiry Overview'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Expiry actions must fit');
      await tester.tap(find.byTooltip('Back'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(expiry.bucket, isNull);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Mark as read').first);
        await tester.pumpAndSettle();
      }
      expect(find.text('No unread notifications'), findsOneWidget);
      expect(notifications.notifications, isEmpty);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(find.byTooltip('Notifications, unread'), findsNothing);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('No unread notifications'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'unread reminders return until explicitly marked read for the day',
    () async {
      final auth = AuthController(_Accounts());
      await auth.initialize();
      final profile = ProfileController(auth, _Preferences());
      await pumpEventQueue();
      final api = ApiClient(
        client: MockClient(
          (_) async => jsonResponse({
            'counts': {'overdue': 1, 'today': 1, 'upcoming': 0},
            'items': <Object>[],
            'total': 2,
            'page': 1,
            'page_size': 20,
          }),
        ),
      );
      final expiry = ExpirySummaryController(
        InventoryRepository(InventoryApiService(api), MemoryTokens()),
      );
      final state = _NotificationState();
      final service = _NotificationService();
      var notifications = AppNotificationController(
        authController: auth,
        profileController: profile,
        expiryController: expiry,
        service: service,
        repository: state,
      );
      await expiry.loadSummary(asOf: DateTime(2026, 9, 30));
      await pumpEventQueue();

      expect(
        notifications.notifications.map((item) => item.type),
        containsAll([
          AppNotificationType.expired,
          AppNotificationType.expiring,
          AppNotificationType.daily,
        ]),
      );

      notifications.dispose();
      notifications = AppNotificationController(
        authController: auth,
        profileController: profile,
        expiryController: expiry,
        service: service,
        repository: state,
      );
      await pumpEventQueue();
      expect(
        notifications.notifications.map((item) => item.type),
        contains(AppNotificationType.expired),
      );

      await notifications.markRead(AppNotificationType.expired);
      notifications.dispose();
      notifications = AppNotificationController(
        authController: auth,
        profileController: profile,
        expiryController: expiry,
        service: service,
        repository: state,
      );
      await pumpEventQueue();
      expect(
        notifications.notifications.map((item) => item.type),
        isNot(contains(AppNotificationType.expired)),
      );
      expect(service.cancelled, contains(NotificationService.expiredItemsId));

      notifications.dispose();
      expiry.dispose();
      profile.dispose();
      auth.dispose();
      api.close();
      service.dispose();
    },
  );
}

class _Accounts implements AuthRepository {
  final user = AppUser(
    id: 'user-1',
    email: 'user@example.com',
    role: 'USER',
    status: 'ACTIVE',
    createdAt: DateTime(2026, 9),
  );

  @override
  Future<AppUser?> restoreSession() async => user;
  @override
  Future<void> logout() async {}
  @override
  Future<AppUser> login({
    required String email,
    required String password,
  }) async => user;
  @override
  Future<AppUser> register({
    required String email,
    required String password,
  }) async => user;
}

class _Preferences implements ProfilePreferencesRepository {
  @override
  Future<ProfilePreferences> read(String userId) async =>
      const ProfilePreferences();
  @override
  Future<void> save(String userId, ProfilePreferences preferences) async {}
}

class _NotificationState extends NotificationStateRepository {
  final values = <String, String>{};

  @override
  Future<String?> readDate(String userId, String type) async =>
      values['$userId-$type'];

  @override
  Future<void> saveDate(String userId, String type, String date) async {
    values['$userId-$type'] = date;
  }
}

class _NotificationService extends NotificationService {
  final cancelled = <int>[];

  @override
  Stream<String> get selectedPayloads => const Stream.empty();

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}
