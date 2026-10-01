import 'package:flutter/material.dart';

import 'scroll_edge_fade.dart';

/// Let conversation content pass behind the floating controls, with a green
/// wash underneath them. The footer's actual height supplies the end padding,
/// including multiline drafts, photo previews and keyboard resizing.
class AssistantScrollLayout extends StatelessWidget {
  const AssistantScrollLayout({
    required this.contentBuilder,
    required this.footer,
    this.header,
    this.bottomInset = 0,
    super.key,
  });

  final Widget Function(BuildContext context, double bottomPadding)
  contentBuilder;
  final Widget footer;
  final Widget? header;
  // Supplied from outside SafeArea, which removes this inset from MediaQuery.
  final double bottomInset;

  static const double _fadeAboveFooter = 24;

  @override
  Widget build(BuildContext context) {
    if (header != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header!,
          Expanded(child: _body(context)),
        ],
      );
    }
    return _body(context);
  }

  Widget _body(BuildContext context) {
    return LayoutBuilder(
      builder: (context, pageConstraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, contentConstraints) {
                final footerHeight =
                    pageConstraints.maxHeight - contentConstraints.maxHeight;
                final viewportHeight = pageConstraints.maxHeight + bottomInset;
                return OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: viewportHeight,
                  maxHeight: viewportHeight,
                  child: ScrollEdgeFade(
                    topExtent: header == null ? 56 : 32,
                    bottomExtent: 0,
                    child: contentBuilder(
                      context,
                      footerHeight + bottomInset + _fadeAboveFooter + 16,
                    ),
                  ),
                );
              },
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -_fadeAboveFooter,
                bottom: -bottomInset,
                left: 0,
                right: 0,
                child: const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00D6EDBE),
                          Color(0x30D6EDBE),
                          Color(0x80D0EAB2),
                          Color(0xC4CCE7AC),
                          Color(0xEDC8E5A7),
                        ],
                        stops: [0, 0.18, 0.48, 0.76, 1],
                      ),
                    ),
                  ),
                ),
              ),
              footer,
            ],
          ),
        ],
      ),
    );
  }
}
