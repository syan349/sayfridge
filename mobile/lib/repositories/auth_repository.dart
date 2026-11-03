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
      _generation++;
      await _clearSessionBestEffort();
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
        await _clearSessionBestEffort();
        onSessionExpired?.call();
      }
      return null;
    }
  }

  /// End-of-session cleanup: in-memory auth must end even when the platform
  /// store cannot be erased. A failure here is swallowed on purpose — the
  /// stored credential has just been rejected by the server, so leftover
  /// bytes authorize nothing and every later renewal is treated as expired.
  Future<void> _clearSessionBestEffort() async {
    try {
      await _tokenStorage.clearSession();
    } catch (_) {}
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

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null) throw const ApiException(statusCode: 401, message: 'Please sign in again.');
    await _authApiService.changePassword(accessToken: token, currentPassword: currentPassword, newPassword: newPassword);
    _generation++;
    // A renewal started before the change must not restore its revoked tokens.
    try { if (_refreshing != null) await _refreshing; } catch (_) { /* Server has already revoked every session. */ }
    try {
      await _tokenStorage.clearSession();
    } catch (_) {
      // The server already committed the change and revoked every session.
      // Reporting a confirmed change as failed would invite a retry that
      // cannot succeed (the current password no longer matches). Any tokens
      // left in storage are revoked server-side: the next request gets 401,
      // renewal fails, and the expired-session path clears them for good.
    }
  }

  Future<void> logout() async {
    // Wait for any rotation before revoking its replacement credential.
    // Its failure must not block revocation of the stored credential.
    try { if (_refreshing != null) await _refreshing; } catch (_) { }
    final refresh = await _tokenStorage.readRefreshToken();
    if (refresh != null) await _authApiService.revoke(refresh);
    _generation++;
    try {
      await _tokenStorage.clearSession();
    } catch (_) {
      // The server confirmed revocation: treat the user as signed out even
      // if the local store cannot be erased right now. Any leftover bytes
      // hold a revoked credential that no longer authorizes anything; the
      // next renewal attempt treats them as a dead session.
    }
  }
}
