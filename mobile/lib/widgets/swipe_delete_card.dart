import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// A bounded left swipe asks for confirmation; it never removes the card itself.
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
  double _offset = 0;
  bool _dragging = false, _confirming = false;
  static const _maxTravel = 56.0;
  static const _triggerDistance = 36.0;
  late final _deleteAction = CustomSemanticsAction(
    label: 'Delete ${widget.itemName}',
  );

  bool get _canSwipe => widget.onDelete != null && !_confirming;

  Future<void> _confirmDeletion() async {
    if (!_canSwipe) return;
    setState(() {
      _offset = 0;
      _dragging = false;
      _confirming = true;
    });
    try {
      await widget.onDelete!();
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _reset() => setState(() {
    _dragging = false;
    _offset = 0;
  });

  @override
  Widget build(BuildContext context) => Semantics(
    customSemanticsActions: !_canSwipe
        ? null
        : {_deleteAction: _confirmDeletion},
    child: GestureDetector(
      onHorizontalDragStart: !_canSwipe
          ? null
          : (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: !_canSwipe
          ? null
          : (details) => setState(
              () =>
                  _offset = (_offset + details.delta.dx).clamp(-_maxTravel, 0),
            ),
      onHorizontalDragEnd: !_canSwipe
          ? null
          : (_) {
              if (_offset <= -_triggerDistance) {
                _confirmDeletion();
              } else {
                _reset();
              }
            },
      onHorizontalDragCancel: _reset,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _offset),
          duration: _dragging
              ? Duration.zero
              : const Duration(milliseconds: 180),
          builder: (context, offset, child) {
            final travel = _dragging ? _offset : offset;
            final strength = (-travel / _triggerDistance).clamp(0.0, 1.0);
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                // Use the Assistant's alpha fade horizontally, restricted to
                // the clipped edge rather than painting a strip over the card.
                final width = math.max(bounds.width, 1.0);
                final extent = math.min(44.0, width * 0.2);
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white.withValues(alpha: 1 - strength),
                    Colors.white,
                    Colors.white,
                  ],
                  stops: [0, extent / width, 1],
                ).createShader(bounds);
              },
              child: Transform.translate(
                offset: Offset(travel, 0),
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}
