import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Visual feedback for the existing hold-to-dictate gesture. Pointer events
/// continue to be delivered to the hold button that received pointer down.
class VoiceRecordingOverlay extends StatelessWidget {
  const VoiceRecordingOverlay({
    required this.words,
    required this.cancelling,
    required this.finishing,
    required this.onClose,
    super.key,
  });

  final String words;
  final bool cancelling, finishing;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = cancelling
        ? const Color(0xFFF45252)
        : AppColors.primary;
    final message = cancelling
        ? 'Release to cancel'
        : finishing
        ? 'Converting speech to text…'
        : words.isEmpty
        ? 'Listening…'
        : words;

    return ColoredBox(
      key: const Key('voice-recording-overlay'),
      color: const Color(0xE8444444),
      child: Stack(
        children: [
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 15,
                  left: 18,
                  child: IconButton(
                    tooltip: 'Cancel voice input',
                    onPressed: onClose,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, -0.12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                key: const Key('voice-input-status'),
                                width: double.infinity,
                                constraints: const BoxConstraints(
                                  minHeight: 88,
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  22,
                                  22,
                                  22,
                                  24,
                                ),
                                decoration: BoxDecoration(
                                  color: bubbleColor,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        message,
                                        maxLines: 5,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: cancelling
                                              ? Colors.white
                                              : Colors.black,
                                          fontSize: 21,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                    if (!cancelling && !finishing) ...[
                                      const SizedBox(width: 10),
                                      const Icon(
                                        Icons.graphic_eq_rounded,
                                        color: Color(0xFF4A672D),
                                        size: 23,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Positioned(
                                right: 38,
                                bottom: -8,
                                child: Transform.rotate(
                                  angle: math.pi / 4,
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: ColoredBox(color: bubbleColor),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                cancelling ? '松手取消' : '松手编辑',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                  fontFamilyFallback: [
                                    'PingFang SC',
                                    'Noto Sans CJK SC',
                                    'Noto Sans SC',
                                    'Microsoft YaHei',
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 220,
            child: IgnorePointer(
              child: _VoiceGestureFooter(cancelling: cancelling),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceGestureFooter extends StatelessWidget {
  const _VoiceGestureFooter({required this.cancelling});

  final bool cancelling;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      return Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _VoiceGesturePainter(cancelling: cancelling),
            ),
          ),
          Positioned(
            left: width * 0.16,
            top: height * 0.34,
            child: Transform.rotate(
              angle: -0.16,
              child: const Text(
                '取消',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontFamilyFallback: [
                    'PingFang SC',
                    'Noto Sans CJK SC',
                    'Noto Sans SC',
                    'Microsoft YaHei',
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: width * 0.62,
            top: height * 0.34,
            child: Transform.rotate(
              angle: 0.10,
              child: const Text(
                '按住识别语音',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontFamilyFallback: [
                    'PingFang SC',
                    'Noto Sans CJK SC',
                    'Noto Sans SC',
                    'Microsoft YaHei',
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _VoiceGesturePainter extends CustomPainter {
  const _VoiceGesturePainter({required this.cancelling});

  final bool cancelling;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final base = Path()
      ..moveTo(0, h * 0.72)
      ..quadraticBezierTo(w * 0.50, h * 0.40, w, h * 0.72)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(base, Paint()..color = const Color(0xFF5A5A5A));

    final left = Path()
      ..moveTo(0, h * 0.32)
      ..quadraticBezierTo(w * 0.24, h * 0.16, w * 0.43, h * 0.19)
      ..quadraticBezierTo(w * 0.58, h * 0.20, w * 0.51, h * 0.46)
      ..quadraticBezierTo(w * 0.47, h * 0.55, 0, h * 0.68)
      ..close();
    canvas.drawPath(
      left,
      Paint()
        ..color = cancelling
            ? const Color(0xFF9B5757)
            : const Color(0xFF646464),
    );

    final right = Path()
      ..moveTo(w * 0.56, h * 0.28)
      ..quadraticBezierTo(w * 0.64, h * 0.08, w * 0.80, h * 0.16)
      ..quadraticBezierTo(w * 0.93, h * 0.22, w, h * 0.28)
      ..lineTo(w, h * 0.70)
      ..quadraticBezierTo(w * 0.77, h * 0.54, w * 0.57, h * 0.50)
      ..quadraticBezierTo(w * 0.51, h * 0.44, w * 0.56, h * 0.28)
      ..close();
    canvas.drawPath(right, Paint()..color = const Color(0xFFE3E3E3));
  }

  @override
  bool shouldRepaint(covariant _VoiceGesturePainter oldDelegate) =>
      oldDelegate.cancelling != cancelling;
}
