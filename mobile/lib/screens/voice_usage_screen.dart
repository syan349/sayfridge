import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/profile_preferences.dart';
import '../widgets/profile_widgets.dart';

class VoiceUsageScreen extends StatelessWidget {
  const VoiceUsageScreen({this.usage, super.key});
  final VoiceUsage? usage;

  @override
  Widget build(BuildContext context) => ProfilePageScaffold(
    title: 'Voice usage',
    topGap: 0,
    children: [
      Text(
        MaterialLocalizations.of(
          context,
        ).formatMonthYear(usage?.period ?? DateTime.now()),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, color: Color(0xFF777777)),
      ),
      const SizedBox(height: 22),
      Center(
        child: Semantics(
          label: usage == null
              ? 'Voice usage unavailable'
              : '${usage!.used} of ${usage!.limit} voice requests used',
          child: SizedBox.square(
            dimension: 224,
            child: CustomPaint(
              painter: _UsageRingPainter(usage?.fraction ?? 0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      usage == null
                          ? '— / —'
                          : '${usage!.used} / ${usage!.limit}',
                      style: const TextStyle(
                        fontSize: 36,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'requests used',
                      style: TextStyle(fontSize: 18, color: Color(0xFF777777)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        usage == null
            ? 'Usage unavailable'
            : '${usage!.remaining} requests left',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 29,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        usage == null
            ? 'Your voice allowance is not available yet.'
            : 'Resets on ${_resetDate(usage!.resetsAt)}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 17, color: Color(0xFF777777)),
      ),
      const SizedBox(height: 23),
      Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB1D68F)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                ProfileIcon(ProfileAssets.info, size: 26),
                SizedBox(width: 13),
                Expanded(
                  child: Text(
                    'What counts?',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            for (var i = 0; i < _rules.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Color(0xFFB1D68F)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _rules[i],
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF777777),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Shared by Add Inventory and AI Assistant.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Color(0xFF808080)),
      ),
      const SizedBox(height: 10),
      const Text(
        'You can keep typing if voice allowance runs out.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Color(0xFF808080)),
      ),
    ],
  );

  static const _rules = [
    'Submitted voice input = 1 request.',
    'Cancelled recordings do not count.',
    'Typing does not use voice allowance.',
  ];

  String _resetDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }
}

class _UsageRingPainter extends CustomPainter {
  const _UsageRingPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = rect.deflate(11);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 21
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD9EDCC);
    canvas.drawOval(ring, paint);
    if (fraction > 0) {
      paint.color = const Color(0xFF81B83E);
      canvas.drawArc(ring, -math.pi / 2, math.pi * 2 * fraction, false, paint);
    }
  }

  @override
  bool shouldRepaint(_UsageRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}
