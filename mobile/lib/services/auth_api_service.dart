import '../models/app_user.dart';
import '../models/auth_session.dart';
import 'api_client.dart';

class AuthApiService {
  const AuthApiService(this._apiClient);

  final ApiClient _apiClient;

  Future<AppUser> register({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.postJson(
      '/auth/register',
      body: {
        'email': email,
        'password': password,
      },
    );

    return AppUser.fromJson(response);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.postJson(
      '/auth/login',
      body: {
        'email': email,
        'password': password,
      },
    );

    return AuthSession.fromJson(response);
  }

  Future<AppUser> getCurrentUser({
    required String accessToken,
  }) async {
    final response = await _apiClient.getJson(
      '/auth/me',
      accessToken: accessToken,
    );

    return AppUser.fromJson(response);
  }
}