import '../models/app_user.dart';
import '../services/api_exception.dart';
import '../services/auth_api_service.dart';
import '../services/token_storage.dart';

class AuthRepository {
  AuthRepository(this._authApiService, this._tokenStorage) {
    _authApiService.setRenewal(renewAccess);
  }

  final AuthApiService _authApiService;
  final TokenStorage _tokenStorage;
  Future<String?>? _refreshing;
  int _generation = 0;
  void Function()? onSessionExpired;

  Future<String?> renewAccess(String rejected) async {
    final stored = await _tokenStorage.readAccessToken();
    if (stored != null && stored != rejected) return stored;
    if (_refreshing != null) return _refreshing;
    final pending = _rotate();
    _refreshing = pending;
    try {
      return await pending;
    } finally {
      if (identical(_refreshing, pending)) _refreshing = null;
    }
  }

  Future<String?> _rotate() async {
    final generation = _generation;
    final refresh = await _tokenStorage.readRefreshToken();
    if (generation != _generation) return null;
    if (refresh == null) {
      await _tokenStorage.clearSession();
      onSessionExpired?.call();
      return null;
    }
    try {
      final session = await _authApiService.refresh(refresh);
      if (generation != _generation) return null;
      await _tokenStorage.saveSession(
        session.accessToken,
        session.refreshToken,
      );
      return session.accessToken;
    } on ApiException catch (error) {
      if (!error.isUnauthorized) {
        rethrow;
      } // Offline refresh preserves the session.
      if (generation == _generation) {
        _generation++;
        await _tokenStorage.clearSession();
        onSessionExpired?.call();
      }
      return null;
    }
  }

  Future<AppUser> register({required String email, required String password}) {
    return _authApiService.register(email: email, password: password);
  }

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    _generation++;
    final session = await _authApiService.login(
      email: email,
      password: password,
    );

    await _tokenStorage.saveSession(session.accessToken, session.refreshToken);
    return session.user;
  }

  Future<AppUser?> restoreSession() async {
    final accessToken = await _tokenStorage.readAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }

    try {
      return await _authApiService.getCurrentUser(accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _tokenStorage.clearSession();
        return null;
      }

      rethrow;
    }
  }

  Future<void> logout() async {
    // Wait for any rotation before revoking its replacement credential.
    if (_refreshing != null) await _refreshing;
    final refresh = await _tokenStorage.readRefreshToken();
    if (refresh != null) await _authApiService.revoke(refresh);
    _generation++;
    await _tokenStorage.clearSession();
  }
}
