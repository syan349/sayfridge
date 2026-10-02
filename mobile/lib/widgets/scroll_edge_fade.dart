import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Fade scrolling content into its existing background without painting over
/// fixed controls or intercepting pointer events. End items remain readable.
class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({
    required this.child,
    this.topExtent = 56,
    this.bottomExtent = 72,
    super.key,
  }) : assert(topExtent > 0),
       assert(bottomExtent >= 0);

  final Widget child;
  final double topExtent, bottomExtent;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  double _before = 0;
  double _after = 0;
  bool _queued = false;

  void _update(ScrollMetrics metrics) {
    final before = metrics.extentBefore;
    final after = metrics.extentAfter;
    if (before == _before && after == _after) return;
    _before = before;
    _after = after;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_queued) return;
      _queued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _queued = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _update(notification.metrics);
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _update(notification.metrics);
            return false;
          },
          child: ClipRect(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                // Short viewports (including an open keyboard) retain a clear
                // middle section rather than letting the two fades overlap.
                final height = math.max(bounds.height, 1.0);
                final top = math.min(widget.topExtent, height * 0.2);
                final bottom = math.min(widget.bottomExtent, height * 0.2);
                final topStrength = (_before / top).clamp(0.0, 1.0);
                final bottomStrength = bottom == 0
                    ? 0.0
                    : (_after / bottom).clamp(0.0, 1.0);
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 1 - topStrength),
                    Colors.white,
                    Colors.white,
                    Colors.white.withValues(alpha: 1 - bottomStrength),
                  ],
                  stops: [0, top / height, 1 - bottom / height, 1],
                ).createShader(bounds);
              },
              child: widget.child,
            ),
          ),
        ),
      );
}
