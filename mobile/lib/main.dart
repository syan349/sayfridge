import 'dart:async';

import 'package:flutter/material.dart';

import 'auth/auth_dependencies.dart';
import 'auth/auth_gate.dart';
import 'models/agent_input_draft.dart';
import 'models/inventory_item.dart';
import 'repositories/catalog_repository.dart';
import 'repositories/inventory_repository.dart';
import 'repositories/profile_preferences_repository.dart';
import 'repositories/storage_space_repository.dart';
import 'repositories/workspace_repository.dart';
import 'screens/ai_assistant_screen.dart';
import 'screens/daily_consumption_recall_screen.dart';
import 'screens/expiring_items_screen.dart';
import 'screens/home_screen.dart';
import 'screens/manual_stock_in_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/catalog_api_service.dart';
import 'services/inventory_api_service.dart';
import 'services/notification_service.dart';
import 'services/storage_space_api_service.dart';
import 'state/agent_controller.dart';
import 'state/app_notification_controller.dart';
import 'state/auth_controller.dart';
import 'state/expiry_summary_controller.dart';
import 'state/inventory_controller.dart';
import 'state/manual_stock_in_controller.dart';
import 'state/profile_controller.dart';
import 'state/storage_space_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/web_safe_area.dart';

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
  late final NotificationService _notificationService;
  late final AppNotificationController _notificationController;
  late final StorageSpaceController _storageSpaceController;
  late final InventoryController _inventoryController;
  late final ExpirySummaryController _expirySummaryController;
  late final ManualStockInController _manualStockInController;
  late final WorkspaceRepository _workspace;
  late final AgentController _agentController;
  final _navigator = GlobalKey<NavigatorState>();
  String? _sessionUser;

  @override
  void initState() {
    super.initState();

    _authDependencies = AuthDependencies.create();
    _notificationService = NotificationService();
    _profileController = ProfileController(
      _authDependencies.authController,
      const ProfilePreferencesRepository(),
      _notificationService,
    );
    _workspace = WorkspaceRepository(
      _authDependencies.apiClient,
      _authDependencies.tokenStorage,
      onChanged: _refreshBusiness,
    );

    final storageSpaceApiService = StorageSpaceApiService(
      _authDependencies.apiClient,
    );
    final storageSpaceRepository = StorageSpaceRepository(
      storageSpaceApiService,
      _authDependencies.tokenStorage,
    );
    _storageSpaceController = StorageSpaceController(
      storageSpaceRepository,
      workspace: _workspace,
    );

    final inventoryApiService = InventoryApiService(
      _authDependencies.apiClient,
    );
    final inventoryRepository = InventoryRepository(
      inventoryApiService,
      _authDependencies.tokenStorage,
    );
    _inventoryController = InventoryController(
      inventoryRepository,
      workspace: _workspace,
    );
    _expirySummaryController = ExpirySummaryController(inventoryRepository);
    _notificationController =
        AppNotificationController(
            authController: _authDependencies.authController,
            profileController: _profileController,
            expiryController: _expirySummaryController,
            service: _notificationService,
          )
          ..onProcessExpired = _openExpiredItemsFromNotification
          ..onDailyCheckIn = _openDailyConsumptionRecall;

    final catalogRepository = CatalogRepository(
      CatalogApiService(_authDependencies.apiClient),
      _authDependencies.tokenStorage,
    );
    _manualStockInController = ManualStockInController(
      catalogRepository,
      inventoryRepository,
      storageSpaceRepository,
    );

    _agentController = AgentController(
      _workspace,
      onInventoryChanged: _refreshBusiness,
    );
    _authDependencies.authController.addListener(_syncSession);
  }

  void _syncSession() {
    final auth = _authDependencies.authController;
    final nextUser = auth.isAuthenticated ? auth.user?.id : null;
    if (nextUser == _sessionUser) return;

    final previousUser = _sessionUser;
    _sessionUser = nextUser;
    _inventoryController.reset();
    _storageSpaceController.reset();
    _expirySummaryController.reset();
    _manualStockInController.reset();
    _agentController.bindUser(nextUser);

    if (previousUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
  }

  Future<void> _refreshBusiness() async {
    if (!_authDependencies.authController.isAuthenticated) return;
    await Future.wait([
      _inventoryController.reload(),
      _storageSpaceController.loadStorageSpaces(),
      _expirySummaryController.reload(),
    ]);
  }

  @override
  void dispose() {
    _authDependencies.authController.removeListener(_syncSession);
    _notificationController.dispose();
    _notificationService.dispose();
    _agentController.dispose();
    _manualStockInController.dispose();
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
    navigator.push(
      MaterialPageRoute<void>(
        builder: (assistantContext) => AiAssistantScreen(
          isGuest: isGuest,
          agentController: _agentController,
          displayName: isGuest ? null : _profileController.displayName,
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

  Future<void> _openManualStockIn(BuildContext context) async {
    final createdItem = await Navigator.of(context).push<InventoryItem>(
      MaterialPageRoute<InventoryItem>(
        builder: (_) =>
            ManualStockInScreen(controller: _manualStockInController),
      ),
    );
    if (createdItem == null) return;
    await _refreshBusiness();
  }

  Future<void> _openExpiredItemsFromNotification() async {
    if (!_authDependencies.authController.isAuthenticated) return;
    await _expirySummaryController.loadSummary(
      asOf: DateUtils.dateOnly(DateTime.now()),
      bucket: 'overdue',
    );
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ExpiringItemsScreen(
          controller: _expirySummaryController,
          inventoryController: _inventoryController,
          storageSpaceController: _storageSpaceController,
        ),
      ),
    );
    await _refreshBusiness();
  }

  Future<void> _openDailyConsumptionRecall() async {
    if (!_authDependencies.authController.isAuthenticated) return;
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    if (!_agentController.canSend) {
      _openAssistant(
        navigator.context,
        _authDependencies.authController,
        isGuest: false,
      );
      return;
    }
    final summary = await navigator.push<AgentInputDraft>(
      MaterialPageRoute<AgentInputDraft>(
        builder: (_) => const DailyConsumptionRecallScreen(),
      ),
    );
    if (!mounted || summary == null || summary.isEmpty) return;
    await _notificationController.markRead(AppNotificationType.daily);
    if (!mounted) return;
    _openDailyConsumptionInAssistant(summary);
  }

  void _openDailyConsumptionInAssistant(AgentInputDraft summary) {
    final navigator = _navigator.currentState;
    final authController = _authDependencies.authController;
    if (navigator == null || !authController.isAuthenticated) return;
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (assistantContext) => AiAssistantScreen(
          agentController: _agentController,
          displayName: _profileController.displayName,
          initialDraft: AgentInputDraft(
            displayText: summary.text.isEmpty ? 'Photo attached' : summary.text,
            text:
                'Today I used: ${summary.text.isEmpty ? "See the attached photos" : summary.text}. Please propose the inventory deductions and wait for my confirmation.',
            images: summary.images,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'SayFridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) => WebSafeArea(child: child!),
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
            key: ValueKey(authController.user!.id),
            expirySummaryController: _expirySummaryController,
            inventoryController: _inventoryController,
            notificationController: _notificationController,
            storageSpaceController: _storageSpaceController,
            onAddItemTap: () => _openManualStockIn(context),
            onDailyConsumptionSubmit: _openDailyConsumptionInAssistant,
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
