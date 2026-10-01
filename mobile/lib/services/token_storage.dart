import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  const TokenStorage([this._storage = const FlutterSecureStorage()]);

  static const String _accessTokenKey = 'auth_access_token';
  static const String _refreshTokenKey = 'auth_refresh_token';
  static const String _sessionKey = 'auth_session';
  final FlutterSecureStorage _storage;

  // One storage write keeps each access/refresh pair together across restarts.
  Future<void> saveSession(String access, String? refresh) => _storage.write(
    key: _sessionKey,
    value: jsonEncode({'access': access, 'refresh': refresh}),
  );

  Future<Map<String, dynamic>?> _readSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  Future<String?> readAccessToken() async {
    final stored = await _readSession();
    return stored == null
        ? _storage.read(key: _accessTokenKey)
        : stored['access'] as String?;
  }

  Future<String?> readRefreshToken() async {
    final stored = await _readSession();
    return stored == null
        ? _storage.read(key: _refreshTokenKey)
        : stored['refresh'] as String?;
  }

  // Legacy access-only callers and stored sessions remain supported.
  Future<void> saveAccessToken(String accessToken) =>
      _storage.write(key: _accessTokenKey, value: accessToken);
  Future<void> deleteAccessToken() => _storage.delete(key: _accessTokenKey);

  Future<void> clearSession() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
