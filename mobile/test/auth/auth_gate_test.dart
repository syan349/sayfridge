import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/auth/auth_gate.dart';
import 'package:sayfridge/models/app_user.dart';
import 'package:sayfridge/repositories/auth_repository.dart';
import 'package:sayfridge/services/api_exception.dart';
import 'package:sayfridge/state/auth_controller.dart';

void main() {
  late AppUser testUser;
  late _FakeAuthRepository repository;
  late AuthController controller;

  setUp(() {
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

  Widget buildGate() {
    return MaterialApp(
      home: AuthGate(
        authController: controller,
        checkingBuilder: (_, _) => const Text('checking'),
        unauthenticatedBuilder: (_, _) => const Text('unauthenticated'),
        authenticatedBuilder: (_, _) => const Text('authenticated'),
        errorBuilder: (_, _) => const Text('error'),
      ),
    );
  }

  testWidgets('shows checking while session restoration is pending', (
    tester,
  ) async {
    repository.restoreCompleter = Completer<AppUser?>();

    await tester.pumpWidget(buildGate());
    await tester.pump();

    expect(find.text('checking'), findsOneWidget);

    repository.restoreCompleter!.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('shows unauthenticated when no session exists', (tester) async {
    await tester.pumpWidget(buildGate());
    await tester.pumpAndSettle();

    expect(find.text('unauthenticated'), findsOneWidget);
  });

  testWidgets('shows authenticated when a session is restored', (tester) async {
    repository.restoredUser = testUser;

    await tester.pumpWidget(buildGate());
    await tester.pumpAndSettle();

    expect(find.text('authenticated'), findsOneWidget);
  });

  testWidgets('shows error when session restoration fails', (tester) async {
    repository.restoreError = const ApiException(
      statusCode: 0,
      code: 'NETWORK_ERROR',
      message: 'Network unavailable',
    );

    await tester.pumpWidget(buildGate());
    await tester.pumpAndSettle();

    expect(find.text('error'), findsOneWidget);
    expect(controller.status, AuthStatus.error);
  });
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

  final AppUser user;

  AppUser? restoredUser;
  Object? restoreError;
  Completer<AppUser?>? restoreCompleter;

  @override
  Future<AppUser?> restoreSession() {
    if (restoreError != null) {
      return Future<AppUser?>.error(restoreError!);
    }

    return restoreCompleter?.future ?? Future<AppUser?>.value(restoredUser);
  }

  @override
  Future<AppUser> register({required String email, required String password}) {
    return Future<AppUser>.value(user);
  }

  @override
  Future<AppUser> login({required String email, required String password}) {
    return Future<AppUser>.value(user);
  }

  @override
  Future<void> logout() {
    return Future<void>.value();
  }
}
