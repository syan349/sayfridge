import 'package:flutter/material.dart';
import 'auth/auth_dependencies.dart';
import 'auth/auth_gate.dart';
import 'screens/ai_assistant_screen.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _authDependencies = AuthDependencies.create();
  }

  @override
  void dispose() {
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
          return const AiAssistantScreen();
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
