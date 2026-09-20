import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  const TokenStorage([
    this._storage = const FlutterSecureStorage(),
  ]);

  static const String _accessTokenKey = 'auth_access_token';

  final FlutterSecureStorage _storage;

  Future<void> saveAccessToken(String accessToken) {
    return _storage.write(
      key: _accessTokenKey,
      value: accessToken,
    );
  }

  Future<String?> readAccessToken() {
    return _storage.read(key: _accessTokenKey);
  }

  Future<void> deleteAccessToken() {
    return _storage.delete(key: _accessTokenKey);
  }
}