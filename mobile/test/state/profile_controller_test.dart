import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/app_user.dart';
import 'package:sayfridge/models/profile_preferences.dart';
import 'package:sayfridge/repositories/auth_repository.dart';
import 'package:sayfridge/repositories/profile_preferences_repository.dart';
import 'package:sayfridge/state/auth_controller.dart';
import 'package:sayfridge/state/profile_controller.dart';

void main() {
  test(
    'late load after logout cannot restore the previous user profile',
    () async {
      final accounts = _Accounts();
      final auth = AuthController(accounts);
      await auth.initialize();
      final storage = _Preferences()
        ..pendingRead = Completer<ProfilePreferences>();
      final profile = ProfileController(auth, storage);
      addTearDown(profile.dispose);
      addTearDown(auth.dispose);
      expect(profile.isLoading, isTrue);
      await auth.logout();
      storage.pendingRead!.complete(
        const ProfilePreferences(fullName: 'Old account'),
      );
      await pumpEventQueue();
      expect(profile.preferences.fullName, isEmpty);
      expect(profile.displayName, 'Guest');
      expect(profile.isLoading, isFalse);
    },
  );

  test('failed saves keep existing preferences and can be retried', () async {
    final auth = AuthController(_Accounts());
    await auth.initialize();
    final storage = _Preferences();
    final profile = ProfileController(auth, storage);
    addTearDown(profile.dispose);
    addTearDown(auth.dispose);
    await pumpEventQueue();
    storage.failSave = true;
    expect(await profile.saveReminders(daysBeforeExpiry: 7), isFalse);
    expect(profile.preferences.daysBeforeExpiry, 3);
    expect(profile.error, contains('Unable to save'));
    expect(profile.isSaving, isFalse);
    storage.failSave = false;
    expect(await profile.saveReminders(daysBeforeExpiry: 7), isTrue);
    expect(profile.preferences.daysBeforeExpiry, 7);
    expect(profile.error, isNull);
  });

  test(
    'in-flight save is scoped to its account when another user signs in',
    () async {
      final accounts = _Accounts();
      final auth = AuthController(accounts);
      await auth.initialize();
      final storage = _Preferences();
      final profile = ProfileController(auth, storage);
      addTearDown(profile.dispose);
      addTearDown(auth.dispose);
      await pumpEventQueue();
      storage.pendingSave = Completer<void>();
      final saving = profile.saveIdentity(
        fullName: 'First user',
        avatarAsset: ProfilePreferences.defaultAvatar,
      );
      await auth.logout();
      accounts.user = _user('second');
      await auth.login(email: 'second@example.com', password: 'test-password');
      await pumpEventQueue();
      storage.pendingSave!.complete();
      expect(await saving, isFalse);
      expect(storage.values['first']!.fullName, 'First user');
      expect(profile.preferences.fullName, isEmpty);
      expect(profile.displayName, 'second');
      expect(profile.isSaving, isFalse);
    },
  );

  test(
    'pending reads do not notify after the controller is disposed',
    () async {
      final auth = AuthController(_Accounts());
      await auth.initialize();
      addTearDown(auth.dispose);
      final storage = _Preferences()
        ..pendingRead = Completer<ProfilePreferences>();
      final profile = ProfileController(auth, storage);
      profile.dispose();
      storage.pendingRead!.complete(const ProfilePreferences());
      await pumpEventQueue();
    },
  );
}

AppUser _user(String id) => AppUser(
  id: id,
  email: '$id@example.com',
  role: 'USER',
  status: 'ACTIVE',
  createdAt: DateTime(2026, 9),
);

class _Accounts implements AuthRepository {
  AppUser user = _user('first');
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
  final values = <String, ProfilePreferences>{};
  Completer<ProfilePreferences>? pendingRead;
  Completer<void>? pendingSave;
  bool failSave = false;

  @override
  Future<ProfilePreferences> read(String userId) async => pendingRead != null
      ? await pendingRead!.future
      : values[userId] ?? const ProfilePreferences();

  @override
  Future<void> save(String userId, ProfilePreferences preferences) async {
    if (failSave) throw StateError('Storage unavailable');
    if (pendingSave != null) await pendingSave!.future;
    values[userId] = preferences;
  }
}
