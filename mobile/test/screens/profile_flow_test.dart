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
import 'package:sayfridge/screens/password_reset_screen.dart';
import 'package:sayfridge/screens/personal_information_screen.dart';
import 'package:sayfridge/screens/profile_screen.dart';
import 'package:sayfridge/screens/reminder_settings_screen.dart';
import 'package:sayfridge/screens/sign_in_screen.dart';
import 'package:sayfridge/screens/voice_usage_screen.dart';
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
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

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
      'Password',
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
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
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
    final tomato = find.byKey(const Key('avatar-tomato'));
    await tester.ensureVisible(tomato);
    await tester.tap(tomato);
    final useAvatar = find.byKey(const Key('use-avatar-button'));
    await tester.ensureVisible(useAvatar);
    await tester.tap(useAvatar);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Alex Chen'), findsOneWidget);
    expect(session.$2.preferences.avatarAsset, contains('tomato_avatar'));
    final stored = await const ProfilePreferencesRepository().read(_user.id);
    expect(stored.fullName, 'Alex Chen');
    expect(stored.avatarAsset, contains('tomato_avatar'));

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
    'password validation, visibility and unsupported submit are honest',
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
      await tester.ensureVisible(find.text('Change password'));
      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();
      expect(find.text('Password change unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reminders persist toggles, lead time and notification time', (
    tester,
  ) async {
    _phoneSize(tester);
    final session = await _session();
    await _showProfile(tester, session.$1, session.$2);
    await tester.tap(find.text('Reminders Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pumpAndSettle();
    expect(session.$2.preferences.expiryReminders, isFalse);
    expect(
      tester
          .widget<DropdownButton<int>>(find.byKey(const Key('reminder-days')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.byType(CupertinoSwitch).first);
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
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, '10');
    await tester.enterText(fields.last, '30');
    await tester.tap(find.text('OK'));
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

  testWidgets('render six reference states for optional visual review', (
    tester,
  ) async {
    _phoneSize(tester);
    final fontPath = Platform.environment['PROFILE_FONT_PATH'];
    if (fontPath != null) {
      await tester.runAsync(() async {
        final loader = FontLoader('Arial');
        loader.addFont(
          Future.value(
            ByteData.sublistView(await File(fontPath).readAsBytes()),
          ),
        );
        await loader.load();
        for (final font in {
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
          'packages/cupertino_icons/CupertinoIcons':
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
        }.entries) {
          await (FontLoader(
            font.key,
          )..addFont(rootBundle.load(font.value))).load();
        }
      });
    }
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

Future<(AuthController, ProfileController)> _session() async {
  const repository = ProfilePreferencesRepository();
  await repository.save(
    _user.id,
    const ProfilePreferences(fullName: 'Demo User'),
  );
  final auth = AuthController(_FakeAuthRepository(_user));
  await auth.initialize();
  final profile = ProfileController(auth);
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

class _FakeAuthRepository implements AuthRepository {
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
