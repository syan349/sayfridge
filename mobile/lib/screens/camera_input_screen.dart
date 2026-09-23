import 'package:flutter/material.dart';

import '../widgets/app_bottom_navigation.dart';

class CameraInputScreen extends StatelessWidget {
  const CameraInputScreen({super.key});

  static const _cameraReference =
      'assets/images/assistant/camera_reference.png';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 86,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 31,
                      ),
                      tooltip: 'Close camera',
                    ),
                    const Icon(
                      Icons.flash_auto_rounded,
                      color: Colors.white,
                      size: 29,
                    ),
                  ],
                ),
              ),
            ),
            AspectRatio(
              aspectRatio: 864 / 1154,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = constraints.maxWidth / 864;
                  return ClipRect(
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          left: -57 * scale,
                          top: -337 * scale,
                          width: 1066 * scale,
                          height: 2088 * scale,
                          child: Image.asset(
                            _cameraReference,
                            fit: BoxFit.fill,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 29),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RoundCameraButton(
                      onTap: () {},
                      child: Image.asset(
                        AssistantAssets.photo,
                        width: 28,
                        height: 28,
                        color: Colors.white,
                        cacheWidth: 96,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: 74,
                        height: 74,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                        ),
                      ),
                    ),
                    _RoundCameraButton(
                      onTap: () {},
                      child: const Icon(
                        Icons.cameraswitch_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundCameraButton extends StatelessWidget {
  const _RoundCameraButton({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF28282A),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(width: 50, height: 50, child: Center(child: child)),
      ),
    );
  }
}
