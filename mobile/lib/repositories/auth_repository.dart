import '../models/app_user.dart';
import '../services/api_exception.dart';
import '../services/auth_api_service.dart';
import '../services/token_storage.dart';

class AuthRepository {
  const AuthRepository(
    this._authApiService,
    this._tokenStorage,
  );

  final AuthApiService _authApiService;
  final TokenStorage _tokenStorage;

  Future<AppUser> register({
    required String email,
    required String password,
  }) {
    return _authApiService.register(
      email: email,
      password: password,
    );
  }

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    final session = await _authApiService.login(
      email: email,
      password: password,
    );

    await _tokenStorage.saveAccessToken(session.accessToken);

    return session.user;
  }

  Future<AppUser?> restoreSession() async {
    final accessToken = await _tokenStorage.readAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }

    try {
      return await _authApiService.getCurrentUser(
        accessToken: accessToken,
      );
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _tokenStorage.deleteAccessToken();
        return null;
      }

      rethrow;
    }
  }

  Future<void> logout() {
    return _tokenStorage.deleteAccessToken();
  }
}