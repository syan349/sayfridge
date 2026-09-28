import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/profile_preferences.dart';
import '../state/auth_controller.dart';
import '../state/profile_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_bottom_navigation.dart';
import '../widgets/app_page_footer.dart';
import '../widgets/profile_widgets.dart';
import 'password_reset_screen.dart';
import 'personal_information_screen.dart';
import 'reminder_settings_screen.dart';
import 'voice_usage_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.authController,
    required this.profileController,
    required this.onAssistantTap,
    required this.onLoginTap,
    this.voiceUsage,
    super.key,
  });

  final AuthController authController;
  final ProfileController profileController;
  final VoidCallback onAssistantTap;
  final VoidCallback onLoginTap;
  // No request-based usage endpoint exists yet. Never substitute voice seconds.
  final VoiceUsage? voiceUsage;

  Future<void> _signOut(BuildContext context) async {
    if (authController.isSubmitting) return;
    final success = await authController.logout();
    if (!context.mounted || success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(authController.errorMessage ?? 'Unable to log out.'),
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    if (!authController.isAuthenticated) {
      onLoginTap();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([authController, profileController]),
    builder: (context, _) {
      final isGuest = !authController.isAuthenticated;
      final preferences = profileController.preferences;
      final canEdit =
          !profileController.isLoading && profileController.error == null;
      return Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(26, 30, 26, 0),
                            sliver: SliverFillRemaining(
                              hasScrollBody: false,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Profile',
                                    style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Center(
                                    child: ProfileAvatar(
                                      asset: isGuest
                                          ? ProfileAssets.guestAvatar
                                          : preferences.avatarAsset,
                                      bytes: isGuest
                                          ? null
                                          : preferences.avatarBytes,
                                    ),
                                  ),
                                  const SizedBox(height: 19),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 83,
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          isGuest
                                              ? 'Guest'
                                              : profileController.displayName,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 23,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          isGuest
                                              ? 'Log in to manage your account\nand preferences.'
                                              : authController.user!.email,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: const Color(0xFF858585),
                                            fontSize: isGuest ? 17 : 15,
                                            height: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  if (!isGuest && profileController.isLoading)
                                    const LinearProgressIndicator(minHeight: 2),
                                  if (!isGuest &&
                                      profileController.error != null)
                                    TextButton.icon(
                                      onPressed: profileController.reload,
                                      icon: const Icon(Icons.refresh),
                                      label: Text(profileController.error!),
                                    ),
                                  _MenuSection(
                                    title: 'Account',
                                    children: [
                                      _MenuRow(
                                        label: isGuest
                                            ? 'Personal Information'
                                            : 'Edit Personal Information',
                                        icon: const ProfileIcon(
                                          ProfileAssets.personalInformation,
                                        ),
                                        locked: isGuest,
                                        onTap: !isGuest && !canEdit
                                            ? null
                                            : () => _open(
                                                context,
                                                PersonalInformationScreen(
                                                  controller: profileController,
                                                ),
                                              ),
                                      ),
                                      _MenuRow(
                                        label: isGuest
                                            ? 'Password'
                                            : 'Password Reset',
                                        icon: const ProfileIcon(
                                          ProfileAssets.password,
                                        ),
                                        locked: isGuest,
                                        onTap: () => _open(
                                          context,
                                          const PasswordResetScreen(),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  _MenuSection(
                                    title: 'Preferences',
                                    children: [
                                      _MenuRow(
                                        label: isGuest
                                            ? 'Reminders'
                                            : 'Reminders Settings',
                                        icon: const Icon(
                                          CupertinoIcons.bell,
                                          size: 24,
                                        ),
                                        locked: isGuest,
                                        onTap: !isGuest && !canEdit
                                            ? null
                                            : () => _open(
                                                context,
                                                ReminderSettingsScreen(
                                                  controller: profileController,
                                                ),
                                              ),
                                      ),
                                      _MenuRow(
                                        label: 'Voice Usage',
                                        icon: const ProfileIcon(
                                          ProfileAssets.voiceUsage,
                                        ),
                                        locked: isGuest,
                                        badge: isGuest || voiceUsage == null
                                            ? null
                                            : '${voiceUsage!.remaining} left',
                                        onTap: () => _open(
                                          context,
                                          VoiceUsageScreen(usage: voiceUsage),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppPageFooter(
                      selectedDestination: AppNavigationDestination.profile,
                      navigationKey: const Key('profile-navigation'),
                      onHomeTap: () => Navigator.of(
                        context,
                      ).popUntil((route) => route.isFirst),
                      onAssistantTap: onAssistantTap,
                      action: isGuest
                          ? GuestLoginButton(
                              key: const Key('profile-login'),
                              onPressed: onLoginTap,
                            )
                          : SizedBox(
                              height: 52,
                              child: OutlinedButton.icon(
                                key: const Key('profile-logout'),
                                onPressed: authController.isSubmitting
                                    ? null
                                    : () => _signOut(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.black,
                                  side: const BorderSide(color: Colors.black),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  textStyle: const TextStyle(
                                    fontFamily: 'Arial',
                                    fontSize: 19,
                                  ),
                                ),
                                icon: const ProfileIcon(ProfileAssets.logout),
                                label: Text(
                                  authController.isSubmitting
                                      ? 'Logging out…'
                                      : 'Log out',
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 5),
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFDFE4D9), width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Color(0xFFDFE4D9)),
              children[i],
            ],
          ],
        ),
      ),
    ],
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.icon,
    required this.locked,
    required this.onTap,
    this.badge,
  });

  final String label;
  final Widget icon;
  final bool locked;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    hint: locked ? 'Log in to access this setting' : null,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 15)),
              ),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(badge!, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 12),
              ],
              if (locked)
                const ProfileIcon(ProfileAssets.lock, size: 27)
              else
                const Icon(CupertinoIcons.chevron_forward, size: 19),
            ],
          ),
        ),
      ),
    ),
  );
}
