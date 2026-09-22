import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

abstract final class AssistantAssets {
  static const root = 'assets/icons/assistant';
  static const add = '$root/add.png';
  static const aiAssistant = '$root/ai_assistant.png';
  static const chat = '$root/chat.png';
  static const home = '$root/home.png';
  static const history = '$root/history.png';
  static const keyboard = '$root/keyboard.png';
  static const microphone = '$root/microphone.png';
  static const photo = '$root/photo.png';
  static const profile = '$root/profile.png';
  static const report = '$root/report.png';
  static const send = '$root/send.png';
  static const update = '$root/update.png';
}

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({this.onHomeTap, this.onProfileTap, super.key});

  final VoidCallback? onHomeTap;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 66,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: const Color(0x10000000), width: 0.7),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    blurRadius: 9,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _NavigationItem(
                      label: 'Home',
                      asset: AssistantAssets.home,
                      onTap: onHomeTap,
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                  Expanded(
                    child: _NavigationItem(
                      label: 'Profile',
                      asset: AssistantAssets.profile,
                      onTap: onProfileTap,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            // Keep the centre label on the same baseline as Home and Profile.
            top: 8,
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(11),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0xFFDCEBD3), spreadRadius: 7),
                    ],
                  ),
                  child: Image.asset(
                    AssistantAssets.chat,
                    fit: BoxFit.contain,
                    cacheWidth: 80,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'AI Assistant',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.asset,
    required this.onTap,
  });

  final String label;
  final String asset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(asset, width: 22, height: 22, cacheWidth: 72),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 11.5, height: 1)),
        ],
      ),
    );
  }
}
