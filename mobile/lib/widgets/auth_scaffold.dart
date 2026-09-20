import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _BackgroundDecoration()),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: IconButton(
                      key: const Key('back-button'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      tooltip: 'Back',
                    ),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundDecoration extends StatelessWidget {
  const _BackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        gradient: RadialGradient(
          center: Alignment(0.9, 0.2),
          radius: 1.25,
          colors: [Color(0xFFEAF9D8), AppColors.background],
        ),
      ),
      child: CustomPaint(painter: _CirclePainter()),
    );
  }
}

class _CirclePainter extends CustomPainter {
  const _CirclePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0C79AF43);
    canvas.drawCircle(
      Offset(size.width * 1.04, size.height * 0.94),
      175,
      paint,
    );
    paint.color = const Color(0x10FFFFFF);
    canvas.drawCircle(
      Offset(size.width * 1.05, size.height * 0.94),
      105,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
