import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'page_scroll_fade.dart';

import '../models/profile_preferences.dart';
import 'app_background.dart';
import 'page_back_button.dart';

abstract final class ProfileAssets {
  static const root = 'assets/icons/profile';
  static const guestAvatar = '$root/guest_avatar.png';
  static const lock = '$root/lock.png';
  static const logout = '$root/logout.png';
  static const password = '$root/password.png';
  static const personalInformation = '$root/personal_information.png';
  static const voiceUsage = '$root/voice_usage.png';
  static const info = '$root/info.png';
  static const warning = '$root/warning.png';
}

class ProfileIcon extends StatelessWidget {
  const ProfileIcon(this.asset, {this.size = 24, super.key});
  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: size,
    height: size,
    fit: BoxFit.contain,
    cacheWidth: (size * 3).ceil(),
    excludeFromSemantics: true,
  );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    this.asset = ProfilePreferences.defaultAvatar,
    this.bytes,
    this.size = 140,
    this.onUpload,
    this.uploading = false,
    super.key,
  });

  final String asset;
  final Uint8List? bytes;
  final double size;
  final VoidCallback? onUpload;
  final bool uploading;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipOval(
            child: bytes == null
                ? Image.asset(
                    asset == ProfilePreferences.defaultAvatar
                        ? 'assets/icons/home/default_avatar.png'
                        : asset,
                    fit: BoxFit.cover,
                    cacheWidth: (size * 3).round(),
                    errorBuilder: (_, _, _) =>
                        Image.asset(ProfilePreferences.defaultAvatar),
                  )
                : Image.memory(
                    bytes!,
                    fit: BoxFit.cover,
                    cacheWidth: (size * 3).round(),
                    errorBuilder: (_, _, _) =>
                        Image.asset(ProfilePreferences.defaultAvatar),
                  ),
          ),
        ),
        if (onUpload != null)
          Positioned(
            right: -1,
            bottom: 2,
            child: SizedBox.square(
              dimension: 44,
              child: IconButton(
                key: const Key('profile-upload-avatar'),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFE5E9DE)),
                ),
                onPressed: uploading ? null : onUpload,
                tooltip: 'Upload avatar',
                icon: uploading
                    ? const SizedBox.square(
                        key: Key('profile-avatar-upload-loading'),
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(CupertinoIcons.share, size: 22),
              ),
            ),
          ),
      ],
    ),
  );
}

class ProfilePageScaffold extends StatelessWidget {
  const ProfilePageScaffold({
    required this.title,
    required this.children,
    this.footer,
    this.topGap = 26,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final Widget? footer;
  final double topGap;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(25, 20, 25, 4),
                  child: SizedBox(
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: const PageBackButton(
                            key: Key('profile-back'),
                            tooltip: 'Back to Profile',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: PageScrollFade(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(horizontal: 25),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(height: topGap),
                                ...children,
                                if (footer != null) ...[
                                  const Spacer(),
                                  const SizedBox(height: 32),
                                  footer!,
                                  SizedBox(
                                    height:
                                        MediaQuery.viewInsetsOf(
                                              context,
                                            ).bottom >
                                            0
                                        ? 24
                                        : 85,
                                  ),
                                ] else
                                  const SizedBox(height: 32),
                              ],
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
    ),
  );
}

class ProfileActionButton extends StatelessWidget {
  const ProfileActionButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF8FBB5C),
        foregroundColor: Colors.black,
        disabledBackgroundColor: const Color(0xFFDCDDDE),
        disabledForegroundColor: const Color(0xFF858585),
        textStyle: const TextStyle(
          fontFamily: 'Arial',
          fontSize: 19,
          fontWeight: FontWeight.w500,
        ),
        shape: const StadiumBorder(),
      ),
      child: busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    ),
  );
}

class ProfileField extends StatelessWidget {
  const ProfileField({
    required this.label,
    required this.controller,
    required this.fieldKey,
    this.hint,
    this.validator,
    this.keyboardType,
    this.isPassword = false,
    this.obscureText = false,
    this.onToggleVisibility,
    this.error,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.autofillHints,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool isPassword;
  final bool obscureText;
  final VoidCallback? onToggleVisibility;
  final String? error;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 9),
      TextFormField(
        key: fieldKey,
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        obscureText: obscureText,
        obscuringCharacter: '●',
        autocorrect: !isPassword,
        enableSuggestions: !isPassword,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 16,
          height: 1.2,
          color: Color(0xFF737373),
        ),
        decoration: InputDecoration(
          hintText: hint,
          errorText: error,
          errorMaxLines: 3,
          errorStyle: const TextStyle(fontSize: 14, color: Colors.red),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 21,
            vertical: 12,
          ),
          suffixIconConstraints: const BoxConstraints(minHeight: 44),
          suffixIcon: isPassword
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (error != null)
                      const ProfileIcon(ProfileAssets.warning, size: 20),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      tooltip: obscureText ? 'Show $label' : 'Hide $label',
                      onPressed: onToggleVisibility,
                      icon: Icon(
                        obscureText
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        color: Colors.black,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 3),
                  ],
                )
              : null,
        ),
      ),
    ],
  );
}

class ProfileCard extends StatelessWidget {
  const ProfileCard({required this.child, this.padding, super.key});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE0E4DC)),
      borderRadius: BorderRadius.circular(9),
    ),
    child: child,
  );
}
