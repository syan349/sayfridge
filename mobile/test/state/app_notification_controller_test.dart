import 'package:sayfridge/models/agent_input_draft.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:sayfridge/widgets/inventory_visuals.dart';

import '../support/integration_fixtures.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['NOTIFICATION_CAPTURE_DIR'] == null) return;
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/arial.ttf').readAsBytes(),
    );
    await (FontLoader('Arial')..addFont(Future.value(font))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'Home bell follows inbox removal and newly available notifications',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _NotificationFixture();
      addTearDown(fixture.dispose);
      await tester.runAsync(fixture.initialize);
      const captureKey = Key('home-notification-capture');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          debugShowCheckedModeBanner: false,
          builder: (context, child) =>
              RepaintBoundary(key: captureKey, child: child!),
          home: HomeScreen(
            onAssistantTap: () {},
            notificationController: fixture.notifications,
            expirySummaryController: fixture.expiry,
            inventoryController: fixture.inventory,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder bell(String asset) => find.byWidgetPredicate((widget) {
        if (widget is! Image) return false;
        var provider = widget.image;
        if (provider is ResizeImage) provider = provider.imageProvider;
        return provider is AssetImage && provider.assetName == asset;
      });
      Future<void> capture(String name) async {
        final directory = Platform.environment['NOTIFICATION_CAPTURE_DIR'];
        if (directory == null) return;
        await tester.runAsync(() async {
          await Future.wait([
            for (final element in find.byType(Image).evaluate())
              precacheImage((element.widget as Image).image, element),
          ]);
        });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(captureKey),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File(
            '$directory/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      expect(bell(HomeAssets.notificationUnread), findsOneWidget);
      await capture('home-notification-unread');
      fixture.overdue = 0;
      await tester.runAsync(() async {
        await fixture.expiry.reload();
        await fixture.inventory.reload();
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      expect(fixture.notifications.hasUnread, isFalse);
      expect(bell(HomeAssets.notificationEmpty), findsOneWidget);
      expect(bell(HomeAssets.notificationUnread), findsNothing);
      await capture('home-notification-empty');
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('No unread notifications'), findsOneWidget);
      await capture('notification-inbox-empty');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      fixture.overdue = 1;
      await tester.runAsync(() async {
        await fixture.expiry.reload();
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      expect(bell(HomeAssets.notificationUnread), findsOneWidget);
      await tester.runAsync(
        () => fixture.notifications.markRead(AppNotificationType.expired),
      );
      await tester.pumpAndSettle();
      expect(bell(HomeAssets.notificationEmpty), findsOneWidget);
      expect(fixture.notifications.hasUnread, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'reading the last notification updates the inbox before OS cancellation',
    () async {
      final fixture = _NotificationFixture();
      addTearDown(fixture.dispose);
      await fixture.initialize();
      expect(fixture.notifications.notifications, hasLength(1));
      fixture.service.cancellation = Completer<void>();
      final marking = fixture.notifications.markRead(
        AppNotificationType.expired,
      );
      await pumpEventQueue();
      expect(fixture.notifications.notifications, isEmpty);
      fixture.service.cancellation!.complete();
      await marking;
    },
  );

  test(
    'a delayed unread query cannot restore an explicitly read notification',
    () async {
      final fixture = _NotificationFixture();
      addTearDown(fixture.dispose);
      await fixture.initialize();
      final delayed = Completer<String?>();
      fixture.state.nextRead = delayed;
      await fixture.expiry.reload();
      await pumpEventQueue();
      await fixture.notifications.markRead(AppNotificationType.expired);
      expect(fixture.notifications.notifications, isEmpty);
      delayed.complete(null); // The query began before the read date was saved.
      await pumpEventQueue();
      expect(fixture.notifications.notifications, isEmpty);
    },
  );

  test(
    'device notifications off suppresses delivery while preserving the in-app inbox',
    () async {
      final auth = AuthController(_Accounts());
      await auth.initialize();
      final service = _NotificationService();
      final profile = ProfileController(auth, _Preferences(), service);
      await pumpEventQueue();
      await profile.setDeviceNotificationsEnabled(false);
      final api = ApiClient(
        client: MockClient(
          (request) async => jsonResponse({
            'counts': {'overdue': 1, 'today': 0, 'upcoming': 0},
            'items': <Object>[],
            'total': 1,
            'page': 1,
            'page_size': 20,
          }),
        ),
      );
      final expiry = ExpirySummaryController(
        InventoryRepository(InventoryApiService(api), MemoryTokens()),
      );
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
        profile.dispose();
        auth.dispose();
        api.close();
        service.dispose();
      });
      await expiry.loadSummary(asOf: DateUtils.dateOnly(DateTime.now()));
      await pumpEventQueue();
      expect(notifications.notifications, isNotEmpty);
      expect(service.shown, isEmpty);
      await profile.setDeviceNotificationsEnabled(true);
      await pumpEventQueue();
      expect(service.shown, contains(NotificationService.expiredItemsId));
    },
  );

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
      AgentInputDraft? dailyUsage;
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
            onDailyConsumptionSubmit: (value) => dailyUsage = value,
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

      await tester.ensureVisible(find.text('Record usage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record usage'));
      await tester.pumpAndSettle();
      expect(find.text('What did you use today?'), findsOneWidget);
      await tester.tap(find.byTooltip('Type a message'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('daily-consumption-input')),
        '3 eggs and 250 ml milk',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(dailyUsage?.text, '3 eggs and 250 ml milk');
      expect(find.text('Daily inventory check-in'), findsNothing);

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

      for (var i = 0; i < 2; i++) {
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

  test('daily notification payload opens the recall flow', () async {
    final auth = AuthController(_Accounts());
    await auth.initialize();
    final profile = ProfileController(auth, _Preferences());
    final api = ApiClient(
      client: MockClient(
        (_) async => jsonResponse({
          'counts': {'overdue': 0, 'today': 0, 'upcoming': 0},
          'items': <Object>[],
          'total': 0,
          'page': 1,
          'page_size': 20,
        }),
      ),
    );
    final expiry = ExpirySummaryController(
      InventoryRepository(InventoryApiService(api), MemoryTokens()),
    );
    final service = _NotificationService();
    final notifications = AppNotificationController(
      authController: auth,
      profileController: profile,
      expiryController: expiry,
      service: service,
      repository: _NotificationState(),
    );
    var opened = false;
    notifications.onDailyCheckIn = () => opened = true;

    service.select('daily');
    await pumpEventQueue();

    expect(opened, isTrue);
    notifications.dispose();
    expiry.dispose();
    profile.dispose();
    auth.dispose();
    api.close();
    service.dispose();
  });
}

class _Accounts implements AuthRepository {
  @override
  void Function()? onSessionExpired;
  @override
  Future<String?> renewAccess(String rejected) async => null;

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
  _Preferences({this.value = const ProfilePreferences()});
  final ProfilePreferences value;
  @override
  Future<ProfilePreferences> read(String userId) async => value;
  @override
  Future<void> save(String userId, ProfilePreferences preferences) async {}
}

class _NotificationState extends NotificationStateRepository {
  final values = <String, String>{};
  Completer<String?>? nextRead;

  @override
  Future<String?> readDate(String userId, String type) async {
    final delayed = nextRead;
    nextRead = null;
    if (delayed != null) return delayed.future;
    return values['$userId-$type'];
  }

  @override
  Future<void> saveDate(String userId, String type, String date) async {
    values['$userId-$type'] = date;
  }
}

class _NotificationService extends NotificationService {
  final cancelled = <int>[];
  final shown = <int>[];
  Completer<void>? cancellation;
  final _selected = StreamController<String>.broadcast();

  @override
  Stream<String> get selectedPayloads => _selected.stream;

  void select(String payload) => _selected.add(payload);

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    await cancellation?.future;
  }

  @override
  Future<NotificationPermissionState> permissionState() async =>
      NotificationPermissionState.enabled;

  @override
  Future<void> synchronizeDailyReminder(ProfilePreferences preferences) async {}

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required String payload,
    bool processAction = false,
  }) async => shown.add(id);

  @override
  void dispose() {
    _selected.close();
    super.dispose();
  }
}

class _NotificationFixture {
  int overdue = 1;
  final auth = AuthController(_Accounts());
  final state = _NotificationState();
  final service = _NotificationService();
  late final ProfileController profile;
  late final ApiClient api;
  late final ExpirySummaryController expiry;
  late final InventoryController inventory;
  late final AppNotificationController notifications;

  Future<void> initialize() async {
    await auth.initialize();
    profile = ProfileController(
      auth,
      _Preferences(value: const ProfilePreferences(dailyCheckIn: false)),
    );
    await pumpEventQueue();
    api = ApiClient(
      client: MockClient(
        (request) async => jsonResponse(
          request.url.path.endsWith('/expiry-summary')
              ? {
                  'counts': {'overdue': overdue, 'today': 0, 'upcoming': 0},
                  'items': [
                    if (overdue > 0) {...stockJson(), 'bucket': 'overdue'},
                  ],
                  'total': overdue,
                  'page': 1,
                  'page_size': 20,
                }
              : {
                  'items': [if (overdue > 0) stockJson()],
                  'total': overdue,
                  'page': 1,
                  'page_size': 20,
                },
        ),
      ),
    );
    expiry = ExpirySummaryController(
      InventoryRepository(InventoryApiService(api), MemoryTokens()),
    );
    inventory = InventoryController(
      InventoryRepository(InventoryApiService(api), MemoryTokens()),
    );
    await inventory.loadInventory();
    notifications = AppNotificationController(
      authController: auth,
      profileController: profile,
      expiryController: expiry,
      service: service,
      repository: state,
    );
    await expiry.loadSummary(asOf: DateUtils.dateOnly(DateTime.now()));
    await pumpEventQueue();
  }

  void dispose() {
    notifications.dispose();
    expiry.dispose();
    inventory.dispose();
    profile.dispose();
    auth.dispose();
    api.close();
    service.dispose();
  }
}
