import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

abstract final class AssistantAssets {
  static const root = 'assets/icons/assistant';
  static const add = '$root/add.png';
  static const aiAssistant = 'assets/icons/home/default_avatar.png';
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
  static const warn = '$root/warn.png';
}

enum AppNavigationDestination { home, assistant, profile }

/// Place at the bottom of a page's SafeArea without additional outer insets.
/// Every tab shares the same geometry; only the selected state changes.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    this.selectedDestination = AppNavigationDestination.assistant,
    this.onHomeTap,
    this.onAssistantTap,
    this.onProfileTap,
    super.key,
  });

  final AppNavigationDestination selectedDestination;
  final VoidCallback? onHomeTap;
  final VoidCallback? onAssistantTap;
  final VoidCallback? onProfileTap;

  static const double bottomSpacing = 28;
  static const double widthFactor = 0.78;
  static const double height = 86;
  static const double extent = height + bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Padding(
        padding: const EdgeInsets.only(bottom: bottomSpacing),
        child: SizedBox(
          height: height,
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
                  key: const Key('app-navigation-bar'),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(
                      color: const Color(0x10000000),
                      width: 0.7,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x24000000),
                        blurRadius: 9,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: FractionallySizedBox(
                  widthFactor: 0.8,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _NavigationItem(
                          label: 'Home',
                          asset: AssistantAssets.home,
                          onTap: onHomeTap,
                          isSelected:
                              selectedDestination ==
                              AppNavigationDestination.home,
                        ),
                      ),
                      Expanded(
                        child: _NavigationItem(
                          label: 'AI Assistant',
                          asset: AssistantAssets.chat,
                          onTap: onAssistantTap,
                          isSelected:
                              selectedDestination ==
                              AppNavigationDestination.assistant,
                          isRaised: true,
                        ),
                      ),
                      Expanded(
                        child: _NavigationItem(
                          label: 'Profile',
                          asset: AssistantAssets.profile,
                          onTap: onProfileTap,
                          isSelected:
                              selectedDestination ==
                              AppNavigationDestination.profile,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.asset,
    required this.onTap,
    required this.isSelected,
    this.isRaised = false,
  });

  final String label;
  final String asset;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isRaised;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isRaised)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: OverflowBox(
                    // Align the entire green disc with the other icons' bottom edge.
                    alignment: Alignment.bottomCenter,
                    minWidth: 58,
                    maxWidth: 58,
                    minHeight: 58,
                    maxHeight: 58,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Color(0xFFDCEBD3),
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Image.asset(
                          asset,
                          fit: BoxFit.contain,
                          cacheWidth: 80,
                        ),
                      ),
                    ),
                  ),
                )
              else
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    isSelected ? AppColors.primary : Colors.black,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    asset,
                    width: 22,
                    height: 22,
                    cacheWidth: 72,
                  ),
                ),
              const SizedBox(height: 3),
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(11.5),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: isSelected ? AppColors.primary : Colors.black,
                      fontSize: 11.5,
                      height: 1,
                      fontWeight: isRaised ? FontWeight.w500 : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
