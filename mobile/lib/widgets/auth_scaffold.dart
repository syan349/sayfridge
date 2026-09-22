import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.child, this.title, super.key});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _BackgroundDecoration()),
          SafeArea(
            child: Column(
              children: [
                if (title == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12, top: 4),
                      child: _BackButton(),
                    ),
                  )
                else
                  SizedBox(
                    height: 56,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: _BackButton(),
                          ),
                        ),
                        Center(
                          child: Text(
                            title!,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                      ],
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

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('back-button'),
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back_ios_new_rounded),
      tooltip: 'Back',
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
