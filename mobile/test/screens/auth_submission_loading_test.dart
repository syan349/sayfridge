import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sayfridge/models/app_user.dart';
import 'package:sayfridge/repositories/auth_repository.dart';
import 'package:sayfridge/repositories/profile_preferences_repository.dart';
import 'package:sayfridge/screens/sign_in_screen.dart';
import 'package:sayfridge/screens/sign_up_screen.dart';
import 'package:sayfridge/state/auth_controller.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('login shows progress and disables repeated submission', (
    tester,
  ) async {
    final repository = _DelayedAuthRepository();
    final controller = AuthController(repository);

    await tester.pumpWidget(
      MaterialApp(home: SignInScreen(authController: controller)),
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-email')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('sign-in-password')),
      'Password123!',
    );
    await tester.tap(find.byKey(const Key('sign-in-button')));
    await tester.pump();

    expect(find.byKey(const Key('auth-loading-indicator')), findsOneWidget);
    expect(_button(tester, 'sign-in-button').onPressed, isNull);
    expect(repository.loginCalls, 1);

    repository.loginCompleter.complete(repository.user);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-loading-indicator')), findsNothing);
  });

  testWidgets('registration shows progress and disables repeated submission', (
    tester,
  ) async {
    final repository = _DelayedAuthRepository();
    final controller = AuthController(repository);

    await tester.pumpWidget(
      MaterialApp(home: SignUpScreen(authController: controller)),
    );
    await tester.enterText(find.byKey(const Key('sign-up-name')), 'Test User');
    await tester.enterText(
      find.byKey(const Key('sign-up-email')),
      'new@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('sign-up-password')),
      'Password123!',
    );
    await tester.enterText(
      find.byKey(const Key('sign-up-confirm-password')),
      'Password123!',
    );
    await tester.ensureVisible(find.byKey(const Key('sign-up-button')));
    await tester.tap(find.byKey(const Key('sign-up-button')));
    await tester.pump();

    expect(find.byKey(const Key('auth-loading-indicator')), findsOneWidget);
    expect(_button(tester, 'sign-up-button').onPressed, isNull);
    expect(repository.registerCalls, 1);

    repository.registerCompleter.complete(repository.user);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-loading-indicator')), findsNothing);
    expect(repository.registerCalls, 1);
    final saved = await const ProfilePreferencesRepository().read(
      repository.user.id,
    );
    expect(saved.fullName, 'Test User');
    expect(saved.avatarAsset, 'assets/images/avatars/default_avatar.png');
  });
}

FilledButton _button(WidgetTester tester, String key) {
  return tester.widget<FilledButton>(
    find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(FilledButton),
    ),
  );
}

class _DelayedAuthRepository implements AuthRepository {
  @override
  void Function()? onSessionExpired;
  @override
  Future<String?> renewAccess(String rejected) async => null;

  final user = AppUser(
    id: 'user-1',
    email: 'user@example.com',
    role: 'USER',
    status: 'ACTIVE',
    createdAt: DateTime.utc(2026, 9, 28),
  );
  final loginCompleter = Completer<AppUser>();
  final registerCompleter = Completer<AppUser>();
  int loginCalls = 0;
  int registerCalls = 0;

  @override
  Future<AppUser> login({required String email, required String password}) {
    loginCalls += 1;
    return loginCompleter.future;
  }

  @override
  Future<AppUser> register({required String email, required String password}) {
    registerCalls += 1;
    return registerCompleter.future;
  }

  @override
  Future<AppUser?> restoreSession() async => null;

  @override
  Future<void> logout() async {}
}
