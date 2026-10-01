import 'package:flutter/material.dart';

import '../screens/ai_assistant_screen.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../widgets/web_safe_area.dart';
import '../theme/app_theme.dart';
import 'preview_session.dart';

/// Standalone debug host that reuses the real screens with isolated fixtures.
class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});

  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final PreviewSession _session;
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _session = PreviewSession();
    _ready = _session.enter();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _openTab(String route) {
    final navigator = _navigator.currentState!;
    if (route == '/assistant') {
      navigator.pushNamed(route);
      return;
    }
    navigator.popUntil((route) => route.isFirst);
    if (route != '/') navigator.pushNamed(route);
  }

  Future<void> _enterPreview() async {
    final enter = await showDialog<bool>(
      context: _navigator.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('Preview account'),
        content: const Text(
          'Demo User\npreview@example.com\n\n'
          'Local UI preview only. No password or backend connection is needed. '
          'Changes are kept in memory until the preview restarts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enter preview'),
          ),
        ],
      ),
    );
    if (!mounted || enter != true) return;
    await _session.enter();
    if (mounted) _openTab('/profile');
  }

  Future<void> _chooseInventory() async {
    final isEmpty = await showDialog<bool>(
      context: _navigator.currentContext!,
      builder: (context) => SimpleDialog(
        title: const Text('Offline Home preview'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Sample data only. No changes are sent to the backend.',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Sample inventory (8 items)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Empty inventory'),
          ),
        ],
      ),
    );
    if (!mounted || isEmpty == null) return;
    // A fresh Home also resets its selected space and scroll position.
    _navigator.currentState!.pushNamedAndRemoveUntil('/', (_) => false);
    await _session.setEmptyInventory(isEmpty);
  }

  Route<void> _route(RouteSettings settings) => MaterialPageRoute<void>(
    settings: settings,
    builder: (context) => switch (settings.name) {
      '/profile' => ProfileScreen(
        authController: _session.auth,
        profileController: _session.profile,
        voiceUsage: _session.voiceUsage,
        onAssistantTap: () => _openTab('/assistant'),
        onLoginTap: _enterPreview,
      ),
      '/assistant' => ListenableBuilder(
        listenable: _session.auth,
        builder: (context, _) => AiAssistantScreen(
          isGuest: !_session.auth.isAuthenticated,
          onLoginTap: _enterPreview,
        ),
      ),
      _ => ListenableBuilder(
        listenable: _session.auth,
        builder: (context, _) => HomeScreen(
          isGuest: !_session.auth.isAuthenticated,
          expirySummaryController: _session.expiry,
          inventoryController: _session.inventory,
          storageSpaceController: _session.spaces,
          onAssistantTap: () => _openTab('/assistant'),
          onProfileTap: () => _openTab('/profile'),
          onLoginTap: _enterPreview,
        ),
      ),
    },
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snapshot) => MaterialApp(
      title: 'SayFridge · UI Preview',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      initialRoute: '/profile',
      onGenerateRoute: _route,
      builder: (context, child) => WebSafeArea(
        child: Builder(
          builder: (context) => Stack(
            fit: StackFit.expand,
            children: [
              if (snapshot.connectionState == ConnectionState.done)
                child!
              else
                const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 2,
                right: 8,
                child: ListenableBuilder(
                  listenable: _session.auth,
                  builder: (context, _) => Material(
                    color: const Color(0xFFFFE8AE),
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      key: const Key('preview-inventory-menu'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: _session.auth.isAuthenticated
                          ? _chooseInventory
                          : null,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Text(
                          'UI PREVIEW · OFFLINE',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF634400),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
