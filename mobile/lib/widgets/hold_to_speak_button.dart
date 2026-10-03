import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Voice input follows one physical pointer: down starts, up stops, cancel
/// aborts. Rebuilding feedback never turns it into a tap-to-toggle recorder.
class HoldToSpeakButton extends StatefulWidget {
  const HoldToSpeakButton({
    required this.enabled,
    required this.recording,
    required this.cancelling,
    required this.finishing,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onCancel,
    this.fontSize = 16,
    super.key,
  });

  final bool enabled, recording, cancelling, finishing;
  final VoidCallback onStart, onEnd, onCancel;
  final ValueChanged<Offset> onMove;
  final double fontSize;

  @override
  State<HoldToSpeakButton> createState() => _HoldToSpeakButtonState();
}

class _HoldToSpeakButtonState extends State<HoldToSpeakButton>
    with WidgetsBindingObserver {
  int? _pointer;
  Offset _origin = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _cancel();
    }
  }

  void _cancel() {
    if (_pointer == null) return;
    _pointer = null;
    widget.onCancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Hold to speak',
    triggerMode: TooltipTriggerMode.manual,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (!widget.enabled ||
            _pointer != null ||
            (event.buttons & kPrimaryButton) == 0) {
          return;
        }
        _pointer = event.pointer;
        _origin = event.position;
        widget.onStart();
      },
      onPointerMove: (event) {
        if (_pointer == event.pointer) widget.onMove(event.position - _origin);
      },
      onPointerUp: (event) {
        if (_pointer != event.pointer) return;
        _pointer = null;
        widget.onEnd();
      },
      onPointerCancel: (event) {
        if (_pointer == event.pointer) _cancel();
      },
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: 'Hold to speak',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: !widget.recording
                ? Colors.transparent
                : widget.cancelling
                ? const Color(0x22FF0000)
                : const Color(0x3391C35E),
          ),
          child: Text(
            widget.finishing
                ? 'Converting speech…'
                : widget.recording
                ? widget.cancelling
                      ? 'Release to cancel'
                      : 'Release to finish'
                : 'Press and hold to speak',
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: widget.fontSize,
              height: 1.15,
              color: widget.cancelling ? Colors.red : const Color(0xFF9999A3),
            ),
          ),
        ),
      ),
    ),
  );
}
