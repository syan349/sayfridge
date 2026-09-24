import '../repositories/auth_repository.dart';
import '../services/api_client.dart';
import '../services/auth_api_service.dart';
import '../services/token_storage.dart';
import '../state/auth_controller.dart';

class AuthDependencies {
  AuthDependencies._({
    required this.apiClient,
    required this.tokenStorage,
    required this.authController,
  });

  factory AuthDependencies.create() {
    final apiClient = ApiClient();
    final authApiService = AuthApiService(apiClient);
    const tokenStorage = TokenStorage();
    final authRepository = AuthRepository(
      authApiService,
      tokenStorage,
    );
    final authController = AuthController(authRepository);

    return AuthDependencies._(
      apiClient: apiClient,
      tokenStorage: tokenStorage,
      authController: authController,
    );
  }

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final AuthController authController;

  void dispose() {
    authController.dispose();
    apiClient.close();
  }
}
