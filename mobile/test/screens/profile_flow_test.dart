import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/main.dart';
import 'package:sayfridge/models/app_user.dart';
import 'package:sayfridge/models/profile_preferences.dart';
import 'package:sayfridge/repositories/auth_repository.dart';
import 'package:sayfridge/repositories/profile_preferences_repository.dart';
import 'package:sayfridge/screens/home_screen.dart';
import 'package:sayfridge/screens/avatar_picker_screen.dart';
import 'package:sayfridge/screens/password_reset_screen.dart';
import 'package:sayfridge/screens/personal_information_screen.dart';
import 'package:sayfridge/screens/profile_screen.dart';
import 'package:sayfridge/screens/reminder_settings_screen.dart';
import 'package:sayfridge/screens/sign_in_screen.dart';
import 'package:sayfridge/screens/sign_up_screen.dart';
import 'package:sayfridge/screens/voice_usage_screen.dart';
import 'package:sayfridge/services/notification_service.dart';
import 'package:sayfridge/state/auth_controller.dart';
import 'package:sayfridge/state/profile_controller.dart';
import 'package:sayfridge/theme/app_theme.dart';

final _user = AppUser(
  id: 'profile-test-user',
  email: 'preview@example.com',
  role: 'USER',
  status: 'ACTIVE',
  createdAt: DateTime(2026, 9, 1),
);

final _usage = VoiceUsage(
  used: 12,
  limit: 50,
  period: DateTime(2026, 9),
  resetsAt: DateTime(2026, 10),
);
const _captureKey = Key('profile-capture');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fontPath = Platform.environment['PROFILE_FONT_PATH'];
    if (fontPath == null) return;
    final fontData = await File(fontPath).readAsBytes();
    for (final family in ['Arial', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(fontData)))).load();
    }
    for (final font in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/cupertino_icons/CupertinoIcons':
          'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final savedName in ['', 'Demo User']) {
    testWidgets('avatar-only edit prefills nickname from "$savedName"', (
      tester,
    ) async {
      _phoneSize(tester);
      const repository = ProfilePreferencesRepository();
      await repository.save(_user.id, ProfilePreferences(fullName: savedName));
      final auth = AuthController(_FakeAuthRepository(_user));
      await auth.initialize();
      final profile = ProfileController(auth, repository);
      addTearDown(profile.dispose);
      addTearDown(auth.dispose);
      await _showProfile(tester, auth, profile);
      final name = profile.displayName;
      await tester.tap(find.text('Edit Personal Information'));
      await tester.pumpAndSettle();
      expect(find.text('Nickname'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('profile-name')))
            .controller!
            .text,
        name,
      );
      await tester.tap(find.text('choose one'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avatar-milk')));
      await tester.tap(find.byKey(const Key('use-avatar-button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonalInformationScreen), findsNothing);
      final stored = await repository.read(_user.id);
      expect(stored.fullName, name);
      expect(stored.avatarAsset, contains('milk_avatar'));
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets('avatar confirmation stays fixed while scrolling at $size', (
      tester,
    ) async {
      _phoneSize(tester, size);
      AvatarChoice? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<AvatarChoice>(
                    MaterialPageRoute(
                      builder: (_) => AvatarPickerScreen(
                        title: 'Avatar library',
                        initialAvatar: avatarChoices.first,
                      ),
                    ),
                  );
                },
                child: const Text('Open library'),
              ),
            ),
          ),
          textScale: size.width == 320 ? 1.5 : 1,
        ),
      );
      await tester.tap(find.text('Open library'));
      await tester.pumpAndSettle();
      // The lazy grid may not build the second row until the large test-font
      // heading scrolls out of a short viewport.
      if (find.byKey(const Key('avatar-carrot')).evaluate().isEmpty) {
        await tester.ensureVisible(find.byKey(const Key('avatar-fridge')));
        await tester.pumpAndSettle();
      }
      final firstRow = avatarChoices
          .take(4)
          .map(
            (choice) => tester.getRect(
              find.byKey(Key('avatar-${choice.name.toLowerCase()}')),
            ),
          )
          .toList();
      for (final rect in firstRow) {
        expect(rect.top, firstRow.first.top);
      }
      expect(
        tester.getRect(find.byKey(const Key('avatar-carrot'))).top,
        greaterThan(firstRow.first.bottom),
      );
      final button = find.byKey(const Key('use-avatar-button'));
      final initialRect = tester.getRect(button);
      final labelRect = tester.getRect(find.text('Use this avatar'));
      expect(labelRect.top, greaterThanOrEqualTo(initialRect.top));
      expect(labelRect.bottom, lessThanOrEqualTo(initialRect.bottom));
      expect(initialRect.bottom, lessThanOrEqualTo(size.height - 34));
      await _capture(tester, 'avatar-library-${size.width.toInt()}');
      await tester.drag(
        find.byKey(const Key('avatar-library-scroll')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      final last = find.byKey(const Key('avatar-fridge spirit rose'));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(tester.getRect(button), initialRect);
      await tester.tap(last);
      await tester.pump();
      await _capture(tester, 'avatar-library-scrolled-${size.width.toInt()}');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(result?.assetPath, avatarChoices.last.assetPath);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('guest Profile routes to login, signup, assistant, and home', (
    tester,
  ) async {
    _phoneSize(tester);
    await tester.pumpWidget(const SayFridgeApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Guest'), findsOneWidget);

    for (final label in [
      'Personal Information',
      'Change password',
      'Reminders',
      'Voice Usage',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Guest'), findsOneWidget);
    }

    await tester.ensureVisible(find.text('Log in / Sign up'));
    await tester.tap(find.text('Log in / Sign up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Guest'), findsOneWidget);
    await tester.tap(find.text('AI Assistant'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile saves name and avatar, cancels drafts, and logs out', (
    tester,
  ) async {
    _phoneSize(tester);
    final session = await _session();
    await _showProfile(tester, session.$1, session.$2);
    expect(find.text('Demo User'), findsOneWidget);
    await tester.tap(find.text('Edit Personal Information'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-name')), 'Alex Chen');
    await tester.tap(find.text('choose one'));
    await tester.pumpAndSettle();
    expect(find.text('Avatar library'), findsOneWidget);
    final rose = find.byKey(const Key('avatar-fridge spirit rose'));
    await tester.ensureVisible(rose);
    await tester.tap(rose);
    final useAvatar = find.byKey(const Key('use-avatar-button'));
    await tester.ensureVisible(useAvatar);
    await tester.tap(useAvatar);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Alex Chen'), findsOneWidget);
    expect(
      session.$2.preferences.avatarAsset,
      contains('fridge_spirit_rose_avatar'),
    );
    final stored = await const ProfilePreferencesRepository().read(_user.id);
    expect(stored.fullName, 'Alex Chen');
    expect(stored.avatarAsset, contains('fridge_spirit_rose_avatar'));

    await tester.tap(find.text('Edit Personal Information'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-name')),
      'Unsaved draft',
    );
    await tester.tap(find.byKey(const Key('profile-back')));
    await tester.pumpAndSettle();
    expect(find.text('Alex Chen'), findsOneWidget);
    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Alex Chen'), findsNothing);
    expect(session.$2.preferences.fullName, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'signing in from guest Profile returns to the signed-in Profile',
    (tester) async {
      _phoneSize(tester);
      final auth = AuthController(_FakeAuthRepository(null));
      await auth.initialize();
      final profile = ProfileController(auth);
      addTearDown(profile.dispose);
      addTearDown(auth.dispose);
      await _showProfile(tester, auth, profile);
      await tester.ensureVisible(find.text('Log in / Sign up'));
      await tester.tap(find.text('Log in / Sign up'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('sign-in-email')),
          matching: find.byType(TextFormField),
        ),
        _user.email,
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('sign-in-password')),
          matching: find.byType(TextFormField),
        ),
        'Password123',
      );
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text(_user.email), findsOneWidget);
      expect(find.text('Edit Personal Information'), findsOneWidget);
      expect(find.text('Guest'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('email changes cannot masquerade as account updates', (
    tester,
  ) async {
    _phoneSize(tester);
    final session = await _session();
    await _showProfile(tester, session.$1, session.$2);
    await tester.tap(find.text('Edit Personal Information'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-email')),
      'changed@example.com',
    );
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Email changes are not available'),
      findsOneWidget,
    );
    expect(session.$1.user!.email, _user.email);
    expect(find.byType(PersonalInformationScreen), findsOneWidget);
  });

  testWidgets(
    'password validation and visibility prevent invalid submissions',
    (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app(const PasswordResetScreen()));
      await tester.pumpAndSettle();
      FilledButton button() => tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('profile-change-password')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button().onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('profile-current-password')),
        'OldPassword123',
      );
      await tester.enterText(
        find.byKey(const Key('profile-new-password')),
        'NewPassword123',
      );
      await tester.enterText(
        find.byKey(const Key('profile-confirm-password')),
        'WrongPassword123',
      );
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(button().onPressed, isNull);
      await tester.tap(find.byTooltip('Show Current password'));
      await tester.pump();
      final currentField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('profile-current-password')),
          matching: find.byType(TextField),
        ),
      );
      expect(currentField.obscureText, isFalse);
      await tester.enterText(
        find.byKey(const Key('profile-confirm-password')),
        'NewPassword123',
      );
      await tester.pump();
      expect(find.text('Passwords do not match'), findsNothing);
      expect(button().onPressed, isNotNull);
      // Successful and failed submissions are exercised in password_change_test.dart.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'device notification switch disables reminder edits and restores saved choices',
    (tester) async {
      _phoneSize(tester);
      final session = await _session();
      await tester.runAsync(() async {
        await pumpEventQueue();
        await session.$2.saveReminders(
          daysBeforeExpiry: 5,
          dailyCheckIn: false,
          notificationHour: 10,
          notificationMinute: 30,
        );
      });
      final savedChoices = session.$2.preferences.toJson();
      await tester.pumpWidget(
        _app(ReminderSettingsScreen(controller: session.$2)),
      );
      await tester.pumpAndSettle();
      final master = find.byKey(const Key('device-notifications-switch'));
      expect(tester.widget<CupertinoSwitch>(master).value, isTrue);

      await tester.tap(master);
      await tester.pumpAndSettle();
      expect(tester.widget<CupertinoSwitch>(master).value, isFalse);
      for (final toggle
          in tester
              .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
              .skip(1)) {
        expect(toggle.onChanged, isNull);
        expect(toggle.value, isFalse);
      }
      expect(
        tester
            .widget<DropdownButton<int>>(find.byKey(const Key('reminder-days')))
            .onChanged,
        isNull,
      );
      await tester.tap(find.byType(CupertinoSwitch).at(1));
      await tester.tap(find.byKey(const Key('reminder-days')));
      await tester.ensureVisible(find.byKey(const Key('reminder-time')));
      await tester.tap(find.byKey(const Key('reminder-time')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsNothing);
      expect(session.$2.preferences.toJson(), {
        ...savedChoices,
        'device_notifications': false,
      });
      final stored = await const ProfilePreferencesRepository().read(_user.id);
      expect(stored.toJson(), session.$2.preferences.toJson());

      await tester.ensureVisible(master);
      await tester.tap(master);
      await tester.pumpAndSettle();
      expect(session.$2.preferences.toJson(), savedChoices);
      final toggles = tester
          .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
          .toList();
      expect(toggles[1].value, isTrue);
      expect(toggles[2].value, isFalse);
      expect(toggles[1].onChanged, isNotNull);
      expect(toggles[2].onChanged, isNotNull);
      await tester.tap(find.byKey(const Key('reminder-days')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 days before').last);
      await tester.pumpAndSettle();
      expect(session.$2.preferences.daysBeforeExpiry, 2);
      await tester.ensureVisible(find.byKey(const Key('reminder-time')));
      await tester.tap(find.byKey(const Key('reminder-time')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save-notification-time')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('denied device permission keeps reminder controls disabled', (
    tester,
  ) async {
    _phoneSize(tester);
    final session = await _session(
      permission: NotificationPermissionState.denied,
    );
    await tester.pumpWidget(
      _app(ReminderSettingsScreen(controller: session.$2)),
    );
    await tester.pumpAndSettle();
    final master = find.byKey(const Key('device-notifications-switch'));
    expect(tester.widget<CupertinoSwitch>(master).value, isFalse);
    await tester.tap(master);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('permission was not granted'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(master).value, isFalse);
    for (final toggle
        in tester
            .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
            .skip(1)) {
      expect(toggle.onChanged, isNull);
      expect(toggle.value, isFalse);
    }
    await tester.ensureVisible(find.byKey(const Key('reminder-time')));
    await tester.tap(find.byKey(const Key('reminder-time')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reminders persist toggles, lead time and notification time', (
    tester,
  ) async {
    _phoneSize(tester);
    final session = await _session();
    await _showProfile(tester, session.$1, session.$2);
    await tester.tap(find.text('Reminders Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch).at(1));
    await tester.pumpAndSettle();
    expect(session.$2.preferences.expiryReminders, isFalse);
    expect(
      tester
          .widget<DropdownButton<int>>(find.byKey(const Key('reminder-days')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.byType(CupertinoSwitch).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reminder-days')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 days before').last);
    await tester.pumpAndSettle();
    expect(session.$2.preferences.daysBeforeExpiry, 5);
    await tester.tap(find.byType(CupertinoSwitch).last);
    await tester.pumpAndSettle();
    expect(session.$2.preferences.dailyCheckIn, isFalse);
    await tester.ensureVisible(find.byKey(const Key('reminder-time')));
    await tester.tap(find.byKey(const Key('reminder-time')));
    await tester.pumpAndSettle();
    final hour = tester.widget<CupertinoPicker>(
      find.byKey(const ValueKey('notification-hour')),
    );
    final minute = tester.widget<CupertinoPicker>(
      find.byKey(const ValueKey('notification-minute')),
    );
    hour.scrollController!.jumpToItem(9);
    minute.scrollController!.jumpToItem(30);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-notification-time')));
    await tester.pumpAndSettle();
    expect(session.$2.preferences.notificationHour, 10);
    expect(session.$2.preferences.notificationMinute, 30);
    await tester.tap(find.byKey(const Key('profile-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reminders Settings'));
    await tester.pumpAndSettle();
    expect(find.text('10:30 AM'), findsOneWidget);
    final stored = await const ProfilePreferencesRepository().read(_user.id);
    expect(stored.daysBeforeExpiry, 5);
    expect(stored.notificationHour, 10);
    expect(stored.dailyCheckIn, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'voice route returns to Profile and unavailable usage is not invented',
    (tester) async {
      _phoneSize(tester);
      final session = await _session();
      await _showProfile(tester, session.$1, session.$2);
      await tester.tap(find.text('Voice Usage'));
      await tester.pumpAndSettle();
      expect(find.text('Usage unavailable'), findsOneWidget);
      expect(find.text('12 / 50'), findsNothing);
      await tester.tap(find.byKey(const Key('profile-back')));
      await tester.pumpAndSettle();
      expect(find.text('Demo User'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all profile pages fit a small phone with larger text', (
    tester,
  ) async {
    _phoneSize(tester, const Size(320, 568));
    final session = await _session();
    final pages = <Widget>[
      ProfileScreen(
        authController: session.$1,
        profileController: session.$2,
        onAssistantTap: () {},
        onLoginTap: () {},
      ),
      PersonalInformationScreen(controller: session.$2),
      const PasswordResetScreen(),
      ReminderSettingsScreen(controller: session.$2),
      VoiceUsageScreen(usage: _usage),
    ];
    for (final page in pages) {
      await tester.pumpWidget(_app(page, textScale: 1.25));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
    }
  });

  testWidgets('render profile and signup states for optional visual review', (
    tester,
  ) async {
    _phoneSize(tester);
    final session = await _session();
    final guest = AuthController(_FakeAuthRepository(null));
    await guest.initialize();
    final guestProfile = ProfileController(guest);
    addTearDown(guestProfile.dispose);
    addTearDown(guest.dispose);
    final pages = <String, Widget>{
      'profile-guest': ProfileScreen(
        authController: guest,
        profileController: guestProfile,
        onAssistantTap: () {},
        onLoginTap: () {},
      ),
      'profile-signed-in': ProfileScreen(
        authController: session.$1,
        profileController: session.$2,
        onAssistantTap: () {},
        onLoginTap: () {},
        voiceUsage: _usage,
      ),
      'profile-personal-information': PersonalInformationScreen(
        controller: session.$2,
      ),
      'profile-password': const PasswordResetScreen(),
      'profile-reminders': ReminderSettingsScreen(controller: session.$2),
      'profile-voice': VoiceUsageScreen(usage: _usage),
      'signup-nickname': SignUpScreen(authController: session.$1),
      'signin-no-social': SignInScreen(authController: session.$1),
    };
    for (final entry in pages.entries) {
      await tester.pumpWidget(_app(entry.value));
      await tester.pumpAndSettle();
      if (entry.key == 'profile-password') {
        await tester.enterText(
          find.byKey(const Key('profile-current-password')),
          'Current123',
        );
        await tester.enterText(
          find.byKey(const Key('profile-new-password')),
          'NewPass123',
        );
        await tester.enterText(
          find.byKey(const Key('profile-confirm-password')),
          'Wrong123',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await _capture(tester, entry.key);
      if (entry.key == 'signin-no-social') {
        await tester.tap(find.text('Forgot password?'));
        await tester.pumpAndSettle();
        await _capture(tester, 'recover-password-dialog');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    }
  });
}

void _phoneSize(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
  theme: AppTheme.light,
  debugShowCheckedModeBanner: false,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: const EdgeInsets.only(top: 47, bottom: 34),
      textScaler: TextScaler.linear(textScale),
    ),
    child: RepaintBoundary(key: _captureKey, child: child),
  ),
  home: home,
);

Future<(AuthController, ProfileController)> _session({
  NotificationPermissionState permission = NotificationPermissionState.enabled,
}) async {
  const repository = ProfilePreferencesRepository();
  await repository.save(
    _user.id,
    const ProfilePreferences(fullName: 'Demo User'),
  );
  final auth = AuthController(_FakeAuthRepository(_user));
  await auth.initialize();
  final notifications = _Notifications(permission);
  final profile = ProfileController(auth, repository, notifications);
  addTearDown(notifications.dispose);
  addTearDown(profile.dispose);
  addTearDown(auth.dispose);
  return (auth, profile);
}

Future<void> _showProfile(
  WidgetTester tester,
  AuthController auth,
  ProfileController profile,
) async {
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navKey,
      theme: AppTheme.light,
      home: const Scaffold(body: Text('Home route')),
    ),
  );
  navKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(
        authController: auth,
        profileController: profile,
        onAssistantTap: () {},
        onLoginTap: () => navKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => SignInScreen(authController: auth),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['PROFILE_SCREENSHOT_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    await Future.wait([
      for (final element in find.byType(Image).evaluate())
        precacheImage((element.widget as Image).image, element),
    ]);
  });
  await tester.pumpAndSettle();
  // Explicit opt-in only: screenshots are review artifacts, not committed goldens.
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
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

class _Notifications extends NotificationService {
  _Notifications(this.permission);
  final NotificationPermissionState permission;

  @override
  Future<NotificationPermissionState> permissionState() async => permission;

  @override
  Future<NotificationPermissionState> requestPermission() async => permission;

  @override
  Future<void> synchronizeDailyReminder(ProfilePreferences preferences) async {}

  @override
  Future<void> cancel(int id) async {}
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    throw UnimplementedError('Use the HTTP-backed password change tests');
  }

  @override
  void Function()? onSessionExpired;
  @override
  Future<String?> renewAccess(String rejected) async => null;

  _FakeAuthRepository(this.user);
  final AppUser? user;
  @override
  Future<AppUser?> restoreSession() async => user;
  @override
  Future<void> logout() async {}
  @override
  Future<AppUser> login({
    required String email,
    required String password,
  }) async => user ?? _user;
  @override
  Future<AppUser> register({
    required String email,
    required String password,
  }) async => user!;
}
