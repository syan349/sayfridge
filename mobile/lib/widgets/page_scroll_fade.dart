import 'package:flutter/material.dart';

import 'scroll_edge_fade.dart';

/// Secondary-page edges fade only while there is more content beyond them.
class PageScrollFade extends StatefulWidget {
  const PageScrollFade({required this.child, super.key});
  final Widget child;

  @override
  State<PageScrollFade> createState() => _PageScrollFadeState();
}

class _PageScrollFadeState extends State<PageScrollFade> {
  double _strength = 0;

  bool _update(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return false;
    final strength = (metrics.extentAfter / 88).clamp(0.0, 1.0);
    if (strength != _strength) setState(() => _strength = strength);
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (event) => _update(event.metrics, event.depth),
        child: NotificationListener<ScrollNotification>(
          onNotification: (event) => _update(event.metrics, event.depth),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ScrollEdgeFade(bottomExtent: 88, child: widget.child),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 88,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _strength,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00D6EDBE), Color(0xE6C8E5A7)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
