import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'app_action_icon.dart';
import '../theme/app_theme.dart';

/// A left swipe reveals an action; only tapping it asks to delete the item.
class SwipeDeleteCard extends StatefulWidget {
  const SwipeDeleteCard({
    required this.child,
    required this.onDelete,
    required this.itemName,
    super.key,
  });
  final Widget child;
  final Future<void> Function()? onDelete;
  final String itemName;
  @override
  State<SwipeDeleteCard> createState() => _SwipeDeleteCardState();
}

class _SwipeDeleteCardState extends State<SwipeDeleteCard> {
  static const _travel = 72.0;
  double _offset = 0;
  bool _dragging = false, _confirming = false;
  bool get _enabled => widget.onDelete != null && !_confirming;

  @override
  void didUpdateWidget(covariant SwipeDeleteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onDelete == null || oldWidget.itemName != widget.itemName) {
      _offset = 0;
      _dragging = false;
    }
  }

  Future<void> _delete() async {
    if (!_enabled) return;
    setState(() {
      _offset = 0;
      _confirming = true;
    });
    try {
      await widget.onDelete!();
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _close() => setState(() {
    _offset = 0;
    _dragging = false;
  });

  @override
  Widget build(BuildContext context) => Semantics(
    customSemanticsActions: !_enabled
        ? null
        : {CustomSemanticsAction(label: 'Delete ${widget.itemName}'): _delete},
    child: GestureDetector(
      onHorizontalDragStart: !_enabled
          ? null
          : (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: !_enabled
          ? null
          : (details) => setState(() {
              _offset = (_offset + details.delta.dx).clamp(-_travel, 0);
            }),
      onHorizontalDragEnd: !_enabled
          ? null
          : (_) => setState(() {
              _offset = _offset <= -32 ? -_travel : 0;
              _dragging = false;
            }),
      onHorizontalDragCancel: _close,
      child: ClipRect(
        clipper: const _SwipeRevealClipper(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 64,
                  height: double.infinity,
                  child: AnimatedOpacity(
                    opacity: _offset == 0 ? 0 : 1,
                    duration: _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: ExcludeSemantics(
                      excluding: _offset == 0,
                      child: Material(
                        color: const Color(0xFFF8DADB),
                        borderRadius: BorderRadius.circular(13),
                        child: InkWell(
                          key: const Key('swipe-delete-action'),
                          borderRadius: BorderRadius.circular(13),
                          onTap: _offset == 0 || !_enabled ? null : _delete,
                          child: Tooltip(
                            message: 'Delete ${widget.itemName}',
                            child: const Center(
                              child: AppActionIcon(ActionAssets.deleteRed),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _offset),
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              builder: (context, offset, child) => Transform.translate(
                offset: Offset(_dragging ? _offset : offset, 0),
                child: child,
              ),
              child: GestureDetector(
                onTap: _offset < 0 ? _close : null,
                child: AbsorbPointer(
                  absorbing: _offset < 0,
                  child: Material(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(13),
                    clipBehavior: Clip.antiAlias,
                    child: widget.child,
                  ),
                ),
              ),
            ),
            Positioned(
              left: -24,
              top: 0,
              bottom: 0,
              width: 48,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: (_offset.abs() / 32).clamp(0.0, 1.0),
                  duration: _dragging
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.background,
                          AppColors.background,
                          Color(0x00F7FDED),
                        ],
                        stops: [0, 0.18, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Let the leading edge fade through the list gutter before it is clipped.
class _SwipeRevealClipper extends CustomClipper<Rect> {
  const _SwipeRevealClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-24, 0, size.width, size.height);

  @override
  bool shouldReclip(_SwipeRevealClipper oldClipper) => false;
}
