import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/profile_preferences.dart';

class ProfilePreferencesRepository {
  const ProfilePreferencesRepository([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  Future<ProfilePreferences> read(String userId) async {
    final value = await _storage.read(key: 'profile_preferences_$userId');
    if (value == null) return const ProfilePreferences();
    return ProfilePreferences.fromJson(
      jsonDecode(value) as Map<String, dynamic>,
    );
  }

  Future<void> save(String userId, ProfilePreferences preferences) =>
      _storage.write(
        key: 'profile_preferences_$userId',
        value: jsonEncode(preferences.toJson()),
      );
}
