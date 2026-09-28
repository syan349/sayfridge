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
      color: const Color(0x88000000),
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
                                cancelling
                                    ? 'Release to cancel'
                                    : 'Release to edit',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
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
            child: _VoiceGestureFooter(
              cancelling: cancelling,
              onCancel: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceGestureFooter extends StatelessWidget {
  const _VoiceGestureFooter({required this.cancelling, required this.onCancel});

  final bool cancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(15, 54, 15, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: GestureDetector(
            key: const Key('voice-cancel-zone'),
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: Container(
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cancelling
                    ? const Color(0xFF9B5757)
                    : const Color(0xFF666666),
                borderRadius: BorderRadius.circular(46),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE3E3E3),
              borderRadius: BorderRadius.circular(46),
            ),
            child: const Text(
              'Hold to speak',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black, fontSize: 16),
            ),
          ),
        ),
      ],
    ),
  );
}
