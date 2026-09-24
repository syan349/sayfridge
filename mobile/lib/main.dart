import 'package:flutter/material.dart';
import 'auth/auth_dependencies.dart';
import 'auth/auth_gate.dart';
import 'repositories/storage_space_repository.dart';
import 'repositories/inventory_repository.dart';
import 'screens/ai_assistant_screen.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/inventory_api_service.dart';
import 'services/storage_space_api_service.dart';
import 'state/expiry_summary_controller.dart';
import 'state/inventory_controller.dart';
import 'state/storage_space_controller.dart';
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
  late final StorageSpaceController _storageSpaceController;
  late final InventoryController _inventoryController;
  late final ExpirySummaryController _expirySummaryController;

  @override
  void initState() {
    super.initState();

    _authDependencies = AuthDependencies.create();

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
    _authDependencies.dispose();
    super.dispose();
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
            onLoginTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SignInScreen(authController: authController),
                ),
              );
            },
            onAssistantTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AiAssistantScreen(isGuest: true),
                ),
              );
            },
            onProfileTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SignInScreen(authController: authController),
                ),
              );
            },
          );
        },
        authenticatedBuilder: (context, authController) {
          return HomeScreen(
            expirySummaryController: _expirySummaryController,
            inventoryController: _inventoryController,
            storageSpaceController: _storageSpaceController,
            onAssistantTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (assistantContext) => AiAssistantScreen(
                    onHomeTap: () => Navigator.of(assistantContext).pop(),
                  ),
                ),
              );
            },
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
