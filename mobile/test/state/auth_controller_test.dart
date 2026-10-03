import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sayfridge/models/app_user.dart';
import 'package:sayfridge/models/profile_preferences.dart';
import 'package:sayfridge/repositories/auth_repository.dart';
import 'package:sayfridge/repositories/profile_preferences_repository.dart';
import 'package:sayfridge/services/api_exception.dart';
import 'package:sayfridge/state/auth_controller.dart';
import 'package:sayfridge/state/profile_controller.dart';

void main() {
  late AppUser testUser;
  late _FakeAuthRepository repository;
  late AuthController controller;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    testUser = AppUser(
      id: 'user-1',
      email: 'user@example.com',
      role: 'USER',
      status: 'ACTIVE',
      createdAt: DateTime.utc(2026, 9, 21),
    );
    repository = _FakeAuthRepository(testUser);
    controller = AuthController(repository);
  });

  tearDown(() {
    controller.dispose();
  });

  group('AuthController', () {
    test('starts in the initial state', () {
      expect(controller.status, AuthStatus.initial);
      expect(controller.user, isNull);
      expect(controller.errorMessage, isNull);
      expect(controller.isSubmitting, isFalse);
    });

    test('initialize becomes unauthenticated without a session', () async {
      await controller.initialize();

      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.user, isNull);
    });

    test('initialize restores an authenticated user', () async {
      repository.restoredUser = testUser;

      await controller.initialize();

      expect(controller.status, AuthStatus.authenticated);
      expect(controller.user, testUser);
      expect(controller.isAuthenticated, isTrue);
    });

    test('initialize exposes a recoverable startup error', () async {
      repository.restoreError = const ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'Network unavailable',
      );

      await controller.initialize();

      expect(controller.status, AuthStatus.error);
      expect(
        controller.errorMessage,
        'Unable to connect to the server. Please try again.',
      );
    });

    test('login exposes submitting state and authenticates the user', () async {
      final completer = Completer<AppUser>();
      repository.loginCompleter = completer;

      final loginFuture = controller.login(
        email: 'user@example.com',
        password: 'Password123!',
      );

      expect(controller.isSubmitting, isTrue);

      completer.complete(testUser);
      final success = await loginFuture;

      expect(success, isTrue);
      expect(controller.isSubmitting, isFalse);
      expect(controller.status, AuthStatus.authenticated);
      expect(controller.user, testUser);
    });

    test('login exposes an authentication error', () async {
      repository.loginError = const ApiException(
        statusCode: 401,
        message: 'Invalid email or password',
      );

      final success = await controller.login(
        email: 'user@example.com',
        password: 'WrongPassword123!',
      );

      expect(success, isFalse);
      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.user, isNull);
      expect(controller.errorMessage, 'Invalid email or password');
      expect(controller.isSubmitting, isFalse);
    });

    test('register succeeds without authenticating the user', () async {
      await controller.initialize();

      final success = await controller.register(
        email: 'new-user@example.com',
        password: 'Password123!',
      );

      expect(success, isTrue);
      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.user, isNull);
    });

    test('register exposes a backend conflict message', () async {
      await controller.initialize();
      repository.registerError = const ApiException(
        statusCode: 409,
        message: 'Email is already registered',
      );

      final success = await controller.register(
        email: 'existing@example.com',
        password: 'Password123!',
      );

      expect(success, isFalse);
      expect(controller.errorMessage, 'Email is already registered');

      controller.clearError();

      expect(controller.errorMessage, isNull);
    });

    test(
      'registration identity survives a new session for the created user',
      () async {
        const profiles = ProfilePreferencesRepository();
        await profiles.save(
          'other-user',
          const ProfilePreferences(fullName: 'Other'),
        );
        expect(
          await controller.register(
            email: testUser.email,
            password: 'Password123!',
            nickname: '  Kiwi  ',
            avatarAsset: 'assets/images/avatars/milk_avatar.png',
          ),
          isTrue,
        );
        final nextAuth = AuthController(repository);
        repository.restoredUser = testUser;
        await nextAuth.initialize();
        final nextProfile = ProfileController(nextAuth, profiles);
        await nextProfile.reload();
        // Construction starts loading; allow that read to finish.
        await Future<void>.delayed(Duration.zero);
        expect(nextProfile.displayName, 'Kiwi');
        expect(nextProfile.preferences.avatarAsset, contains('milk_avatar'));
        expect((await profiles.read('other-user')).fullName, 'Other');
        nextProfile.dispose();
        nextAuth.dispose();
      },
    );

    test(
      'local identity failure still reports successful account creation',
      () async {
        final auth = AuthController(repository, _FailingProfiles());
        expect(
          await auth.register(
            email: testUser.email,
            password: 'Password123!',
            nickname: 'Kiwi',
          ),
          isTrue,
        );
        expect(auth.status, AuthStatus.unauthenticated);
        expect(auth.errorMessage, contains('Account created. Please sign in.'));
        expect(auth.errorMessage, contains('could not be saved'));
        auth.dispose();
      },
    );

    test('logout clears the authenticated user', () async {
      repository.restoredUser = testUser;
      await controller.initialize();

      final success = await controller.logout();

      expect(success, isTrue);
      expect(repository.logoutCalled, isTrue);
      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.user, isNull);
    });
  });
}

class _FailingProfiles extends ProfilePreferencesRepository {
  @override
  Future<void> save(String userId, ProfilePreferences preferences) async {
    throw StateError('Storage unavailable');
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  void Function()? onSessionExpired;
  @override
  Future<String?> renewAccess(String rejected) async => null;

  _FakeAuthRepository(this.user);

  final AppUser user;

  AppUser? restoredUser;
  Object? restoreError;
  Object? registerError;
  Object? loginError;
  Object? logoutError;
  Completer<AppUser>? loginCompleter;
  bool logoutCalled = false;

  @override
  Future<AppUser> register({required String email, required String password}) {
    if (registerError != null) {
      return Future<AppUser>.error(registerError!);
    }

    return Future<AppUser>.value(user);
  }

  @override
  Future<AppUser> login({required String email, required String password}) {
    if (loginError != null) {
      return Future<AppUser>.error(loginError!);
    }

    return loginCompleter?.future ?? Future<AppUser>.value(user);
  }

  @override
  Future<AppUser?> restoreSession() {
    if (restoreError != null) {
      return Future<AppUser?>.error(restoreError!);
    }

    return Future<AppUser?>.value(restoredUser);
  }

  @override
  Future<void> logout() {
    logoutCalled = true;

    if (logoutError != null) {
      return Future<void>.error(logoutError!);
    }

    return Future<void>.value();
  }
}
