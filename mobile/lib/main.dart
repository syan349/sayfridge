import 'package:flutter/material.dart';
import 'auth/auth_dependencies.dart';
import 'auth/auth_gate.dart';
import 'repositories/storage_space_repository.dart';
import 'repositories/inventory_repository.dart';
import 'screens/ai_assistant_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/inventory_api_service.dart';
import 'services/storage_space_api_service.dart';
import 'state/expiry_summary_controller.dart';
import 'state/inventory_controller.dart';
import 'state/storage_space_controller.dart';
import 'state/auth_controller.dart';
import 'state/profile_controller.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const SayFridgeApp());
}

class SayFridgeApp extends StatefulWidget {
  const SayFridgeApp({super.key});

  @override
  State<SayFridgeApp> createState() => _SayFridgeAppState();
}

class _SayFridgeAppState extends State<SayFridgeApp> {
  late final AuthDependencies _authDependencies;
  late final ProfileController _profileController;
  late final StorageSpaceController _storageSpaceController;
  late final InventoryController _inventoryController;
  late final ExpirySummaryController _expirySummaryController;

  @override
  void initState() {
    super.initState();

    _authDependencies = AuthDependencies.create();
    _profileController = ProfileController(_authDependencies.authController);

    final storageSpaceApiService = StorageSpaceApiService(
      _authDependencies.apiClient,
    );
    final storageSpaceRepository = StorageSpaceRepository(
      storageSpaceApiService,
      _authDependencies.tokenStorage,
    );

    _storageSpaceController = StorageSpaceController(storageSpaceRepository);

    final inventoryApiService = InventoryApiService(
      _authDependencies.apiClient,
    );
    final inventoryRepository = InventoryRepository(
      inventoryApiService,
      _authDependencies.tokenStorage,
    );

    _inventoryController = InventoryController(inventoryRepository);
    _expirySummaryController = ExpirySummaryController(inventoryRepository);
  }

  @override
  void dispose() {
    _expirySummaryController.dispose();
    _inventoryController.dispose();
    _storageSpaceController.dispose();
    _profileController.dispose();
    _authDependencies.dispose();
    super.dispose();
  }

  void _openSignIn(BuildContext context, AuthController authController) {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SignInScreen(authController: authController),
      ),
    );
  }

  void _openAssistant(
    BuildContext context,
    AuthController authController, {
    required bool isGuest,
  }) {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (assistantContext) => AiAssistantScreen(
          isGuest: isGuest,
          onHomeTap: () =>
              Navigator.of(assistantContext).popUntil((route) => route.isFirst),
          onProfileTap: () => _openProfile(assistantContext, authController),
          onLoginTap: isGuest
              ? () => _openSignIn(assistantContext, authController)
              : null,
        ),
      ),
    );
  }

  void _openProfile(BuildContext context, AuthController authController) {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (profileContext) => ProfileScreen(
          authController: authController,
          profileController: _profileController,
          onAssistantTap: () => _openAssistant(
            profileContext,
            authController,
            isGuest: !authController.isAuthenticated,
          ),
          onLoginTap: () => Navigator.of(profileContext).push(
            MaterialPageRoute<void>(
              builder: (_) => SignInScreen(authController: authController),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SayFridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AuthGate(
        authController: _authDependencies.authController,
        checkingBuilder: (context, authController) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
        unauthenticatedBuilder: (context, authController) {
          return HomeScreen(
            isGuest: true,
            onLoginTap: () => _openSignIn(context, authController),
            onAssistantTap: () =>
                _openAssistant(context, authController, isGuest: true),
            onProfileTap: () => _openProfile(context, authController),
          );
        },
        authenticatedBuilder: (context, authController) {
          return HomeScreen(
            expirySummaryController: _expirySummaryController,
            inventoryController: _inventoryController,
            storageSpaceController: _storageSpaceController,
            onAssistantTap: () =>
                _openAssistant(context, authController, isGuest: false),
            onProfileTap: () => _openProfile(context, authController),
          );
        },
        errorBuilder: (context, authController) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: authController.initialize,
                child: const Text('Try again'),
              ),
            ),
          );
        },
      ),
    );
  }
}
