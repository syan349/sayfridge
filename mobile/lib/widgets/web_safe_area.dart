import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../platform/css_safe_area.dart'
    if (dart.library.js_interop) '../platform/css_safe_area_web.dart';

/// Provide browser safe-area insets without shrinking the Navigator/Overlay.
class WebSafeArea extends StatelessWidget {
  const WebSafeArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cssPadding = readCssSafeArea();
    if (cssPadding == EdgeInsets.zero) return child;
    final data = MediaQuery.of(context);
    final viewPadding = EdgeInsets.fromLTRB(
      math.max(data.viewPadding.left, cssPadding.left),
      math.max(data.viewPadding.top, cssPadding.top),
      math.max(data.viewPadding.right, cssPadding.right),
      math.max(data.viewPadding.bottom, cssPadding.bottom),
    );
    return MediaQuery(
      data: data.copyWith(
        viewPadding: viewPadding,
        padding: EdgeInsets.fromLTRB(
          math.max(0, viewPadding.left - data.viewInsets.left),
          math.max(0, viewPadding.top - data.viewInsets.top),
          math.max(0, viewPadding.right - data.viewInsets.right),
          math.max(0, viewPadding.bottom - data.viewInsets.bottom),
        ),
      ),
      child: child,
    );
  }
}
