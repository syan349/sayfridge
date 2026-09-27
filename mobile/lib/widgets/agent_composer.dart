import 'package:flutter/material.dart';

import 'app_bottom_navigation.dart';

/// Presentation only: sending, image selection and voice gestures stay with
/// AgentConversationScreen and its existing controller/services.
class AgentComposer extends StatefulWidget {
  const AgentComposer({
    required this.controller,
    required this.enabled,
    required this.hasImages,
    required this.onPhotoPressed,
    required this.onSendPressed,
    required this.voiceButton,
    this.waiting = false,
    this.voiceActive = false,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled, hasImages, waiting, voiceActive;
  final VoidCallback? onPhotoPressed, onSendPressed;
  final Widget voiceButton;

  @override
  State<AgentComposer> createState() => _AgentComposerState();
}

class _AgentComposerState extends State<AgentComposer> {
  final _focusNode = FocusNode();
  bool _typing = false;
  late String _lastText;

  @override
  void initState() {
    super.initState();
    _typing = widget.controller.text.isNotEmpty;
    _lastText = widget.controller.text;
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant AgentComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
      _lastText = widget.controller.text;
    }
  }

  void _refresh() {
    setState(() {
      // Released speech becomes editable text; it is never sent here.
      if (widget.controller.text != _lastText &&
          widget.controller.text.isNotEmpty) {
        _typing = true;
      }
      _lastText = widget.controller.text;
    });
  }

  void _typeMessage() {
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _voiceMode() {
    _focusNode.unfocus();
    setState(() => _typing = false);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 60),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 10,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        _ComposerButton(
          tooltip: 'Add photos',
          icon: const Icon(
            Icons.image_outlined,
            color: Color(0xFF81848A),
            size: 25,
          ),
          onPressed: widget.voiceActive ? null : widget.onPhotoPressed,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _typing || widget.waiting
              ? TextField(
                  key: const Key('assistant-message-field'),
                  controller: widget.controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled && !widget.voiceActive,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 8000,
                  textInputAction: TextInputAction.send,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    counterText: '',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    hintText: widget.waiting
                        ? 'Answer the pending items above'
                        : 'Send message ...',
                    hintStyle: const TextStyle(
                      color: Color(0xFFA4A4AE),
                      fontSize: 16,
                    ),
                  ),
                  onSubmitted: (_) => widget.onSendPressed?.call(),
                )
              : widget.voiceButton,
        ),
        if (_typing || widget.waiting) ...[
          _ComposerButton(
            tooltip: 'Switch to voice input',
            icon: Image.asset(
              AssistantAssets.microphone,
              width: 23,
              height: 29,
            ),
            onPressed: widget.enabled && !widget.voiceActive
                ? _voiceMode
                : null,
          ),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            color: const Color(0xFFC6C6CB),
          ),
        ] else
          _ComposerButton(
            tooltip: 'Type a message',
            icon: Image.asset(AssistantAssets.keyboard, width: 28, height: 24),
            onPressed: widget.enabled && !widget.voiceActive
                ? _typeMessage
                : null,
          ),
        if (_typing || widget.waiting || widget.hasImages)
          _ComposerButton(
            tooltip: 'Send message',
            icon: Image.asset(AssistantAssets.send, width: 26, height: 24),
            onPressed: widget.voiceActive ? null : widget.onSendPressed,
          ),
      ],
    ),
  );
}

class _ComposerButton extends StatelessWidget {
  const _ComposerButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(width: 38, height: 42),
    padding: const EdgeInsets.all(5),
    icon: Opacity(opacity: onPressed == null ? 0.4 : 1, child: icon),
  );
}
