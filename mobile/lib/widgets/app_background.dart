import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared background used by authentication and the main mobile experience.
class AppBackground extends StatelessWidget {
  const AppBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        gradient: RadialGradient(
          center: Alignment(0.9, 0.2),
          radius: 1.25,
          colors: [Color(0xFFEAF9D8), AppColors.background],
        ),
      ),
      child: CustomPaint(
        painter: const _BackgroundCirclePainter(),
        child: child,
      ),
    );
  }
}

class _BackgroundCirclePainter extends CustomPainter {
  const _BackgroundCirclePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0F79AF43)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.15;
    canvas.drawCircle(
      Offset(size.width * 1.04, size.height * 0.94),
      size.width * 0.30,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
