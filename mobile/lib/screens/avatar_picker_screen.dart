import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_widgets.dart';

class AvatarChoice {
  const AvatarChoice({required this.name, required this.assetPath});

  final String name;
  final String assetPath;
}

const avatarChoices = <AvatarChoice>[
  AvatarChoice(
    name: 'Fridge',
    assetPath: 'assets/images/avatars/default_avatar.png',
  ),
  AvatarChoice(
    name: 'Milk',
    assetPath: 'assets/images/avatars/milk_avatar.png',
  ),
  AvatarChoice(
    name: 'Avocado',
    assetPath: 'assets/images/avatars/avocado_avatar.png',
  ),
  AvatarChoice(
    name: 'Broccoli',
    assetPath: 'assets/images/avatars/broccoli_avatar.png',
  ),
  AvatarChoice(
    name: 'Carrot',
    assetPath: 'assets/images/avatars/carrot_avatar.png',
  ),
  AvatarChoice(
    name: 'Lemon',
    assetPath: 'assets/images/avatars/lemon_avatar.png',
  ),
  AvatarChoice(
    name: 'Strawberry',
    assetPath: 'assets/images/avatars/strawberry_avatar.png',
  ),
  AvatarChoice(
    name: 'Mushroom',
    assetPath: 'assets/images/avatars/mushroom_avatar.png',
  ),
  AvatarChoice(name: 'Egg', assetPath: 'assets/images/avatars/egg_avatar.png'),
  AvatarChoice(
    name: 'Pear',
    assetPath: 'assets/images/avatars/pear_avatar.png',
  ),
  AvatarChoice(
    name: 'Bread',
    assetPath: 'assets/images/avatars/bread_avatar.png',
  ),
  AvatarChoice(
    name: 'Tomato',
    assetPath: 'assets/images/avatars/tomato_avatar.png',
  ),
  AvatarChoice(
    name: 'Chibi Green',
    assetPath: 'assets/images/avatars/chibi_green_avatar.png',
  ),
  AvatarChoice(
    name: 'Chibi Apricot',
    assetPath: 'assets/images/avatars/chibi_apricot_avatar.png',
  ),
  AvatarChoice(
    name: 'Chibi Blue',
    assetPath: 'assets/images/avatars/chibi_blue_avatar.png',
  ),
  AvatarChoice(
    name: 'Chibi Latte',
    assetPath: 'assets/images/avatars/chibi_latte_avatar.png',
  ),
  AvatarChoice(
    name: 'Chibi Lavender',
    assetPath: 'assets/images/avatars/chibi_lavender_avatar.png',
  ),
  AvatarChoice(
    name: 'Chibi Pink',
    assetPath: 'assets/images/avatars/chibi_pink_avatar.png',
  ),
  AvatarChoice(
    name: 'Fridge Spirit Green',
    assetPath: 'assets/images/avatars/fridge_spirit_green_avatar.png',
  ),
  AvatarChoice(
    name: 'Fridge Spirit Latte',
    assetPath: 'assets/images/avatars/fridge_spirit_latte_avatar.png',
  ),
  AvatarChoice(
    name: 'Fridge Spirit Melon',
    assetPath: 'assets/images/avatars/fridge_spirit_melon_avatar.png',
  ),
  AvatarChoice(
    name: 'Fridge Spirit Mint',
    assetPath: 'assets/images/avatars/fridge_spirit_mint_avatar.png',
  ),
  AvatarChoice(
    name: 'Fridge Spirit Periwinkle',
    assetPath: 'assets/images/avatars/fridge_spirit_periwinkle_avatar.png',
  ),
  AvatarChoice(
    name: 'Fridge Spirit Rose',
    assetPath: 'assets/images/avatars/fridge_spirit_rose_avatar.png',
  ),
];

class AvatarPickerScreen extends StatefulWidget {
  const AvatarPickerScreen({
    required this.initialAvatar,
    this.isFinalStep = false,
    this.title = 'Create Account',
    super.key,
  });

  final AvatarChoice initialAvatar;
  final bool isFinalStep;
  final String title;

  @override
  State<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends State<AvatarPickerScreen> {
  late AvatarChoice _selected = widget.initialAvatar;

  void _finish() {
    if (widget.isFinalStep) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account with ${_selected.name} avatar is ready to connect to the API.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop(_selected);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: AuthContent(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Choose your avatar',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 5),
            const Text(
              'Pick one you like.',
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 26),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: avatarChoices.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 24,
                crossAxisSpacing: 24,
              ),
              itemBuilder: (context, index) {
                final choice = avatarChoices[index];
                return AvatarBubble(
                  key: Key('avatar-${choice.name.toLowerCase()}'),
                  choice: choice,
                  selected: identical(choice, _selected),
                  onTap: () => setState(() => _selected = choice),
                );
              },
            ),
            const SizedBox(height: 32),
            const SizedBox(height: 18),
            PrimaryAuthButton(
              key: const Key('use-avatar-button'),
              label: 'Use this avatar',
              onPressed: _finish,
            ),
          ],
        ),
      ),
    );
  }
}

class AvatarBubble extends StatelessWidget {
  const AvatarBubble({
    required this.choice,
    this.size,
    this.imageBytes,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final AvatarChoice choice;
  final double? size;
  final Uint8List? imageBytes;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bubble = LayoutBuilder(
      builder: (context, constraints) {
        final resolvedSize = size ?? constraints.biggest.shortestSide;
        return SizedBox.square(
          dimension: resolvedSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  foregroundDecoration: selected
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary,
                            width: 3,
                          ),
                        )
                      : null,
                  child: ClipOval(
                    child: imageBytes == null
                        ? Image.asset(
                            choice.assetPath,
                            fit: BoxFit.cover,
                            cacheWidth: (resolvedSize * 3).ceil(),
                          )
                        : Image.memory(
                            imageBytes!,
                            fit: BoxFit.cover,
                            cacheWidth: (resolvedSize * 3).ceil(),
                          ),
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  right: -1,
                  bottom: 0,
                  child: SizedBox(
                    width: resolvedSize * 0.3,
                    height: resolvedSize * 0.3,
                    child: Material(
                      color: AppColors.primary,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: null,
                        customBorder: const CircleBorder(),
                        child: Icon(
                          Icons.check,
                          size: resolvedSize * 0.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '${choice.name} avatar',
      child: onTap == null
          ? bubble
          : InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: bubble,
            ),
    );
  }
}
