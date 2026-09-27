import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_bottom_navigation.dart';

/// Shared bottom layout for the guest tabs, measured from the Home design.
/// Place inside a SafeArea so the action and navigation stay above system UI.
class AppPageFooter extends StatelessWidget {
  const AppPageFooter({
    required this.action,
    required this.selectedDestination,
    this.showLoginHint = false,
    this.onHomeTap,
    this.onAssistantTap,
    this.onProfileTap,
    this.navigationKey,
    super.key,
  });

  final Widget action;
  final AppNavigationDestination selectedDestination;
  final bool showLoginHint;
  final VoidCallback? onHomeTap;
  final VoidCallback? onAssistantTap;
  final VoidCallback? onProfileTap;
  final Key? navigationKey;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(26, 14, 26, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLoginHint) ...[
              const Text(
                'Log in to start your own inventory.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: AppColors.muted),
              ),
              const SizedBox(height: 17),
            ],
            action,
          ],
        ),
      ),
      Padding(
        // Keep the footer 28 logical pixels above the enclosing bottom safe area.
        padding: const EdgeInsets.fromLTRB(35, 0, 35, 28),
        child: AppBottomNavigation(
          key: navigationKey,
          selectedDestination: selectedDestination,
          onHomeTap: onHomeTap,
          onAssistantTap: onAssistantTap,
          onProfileTap: onProfileTap,
        ),
      ),
    ],
  );
}

class GuestLoginButton extends StatelessWidget {
  const GuestLoginButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
      child: const Text(
        'Log in / Sign up',
        style: TextStyle(fontSize: 18, color: Colors.black),
      ),
    ),
  );
}
