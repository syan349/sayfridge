import 'package:flutter/material.dart';

import 'app_bottom_navigation.dart';

/// Shared right edge for example cards and real inventory/expiry list cards.
class InventoryCardTrailing extends StatelessWidget {
  const InventoryCardTrailing({
    required this.expiryText,
    required this.expiryColor,
    this.showWarning = false,
    this.maxWidth = 112,
    super.key,
  });

  final String expiryText;
  final Color expiryColor;
  final bool showWarning;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showWarning) ...[
              Image.asset(
                AssistantAssets.warn,
                width: 19,
                height: 19,
                fit: BoxFit.contain,
                cacheWidth: 64,
                excludeFromSemantics: true,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                expiryText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: expiryColor, fontSize: 14.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'View item',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5),
              ),
            ),
            SizedBox(width: 5),
            // Tight bounds align the visible tip with the expiry text's edge.
            SizedBox(
              width: 7,
              height: 12,
              child: CustomPaint(painter: _CardChevron()),
            ),
          ],
        ),
      ],
    ),
  );
}

class _CardChevron extends CustomPainter {
  const _CardChevron();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(.75, .75)
        ..lineTo(size.width - .75, size.height / 2)
        ..lineTo(.75, size.height - .75),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CardChevron oldDelegate) => false;
}
