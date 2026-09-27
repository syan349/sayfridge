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
    required this.voiceButtonBuilder,
    this.waiting = false,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled, hasImages, waiting;
  final VoidCallback? onPhotoPressed, onSendPressed;
  final Widget Function(bool expanded) voiceButtonBuilder;

  @override
  State<AgentComposer> createState() => _AgentComposerState();
}

class _AgentComposerState extends State<AgentComposer> {
  final _focusNode = FocusNode();
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _typing = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant AgentComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  void _refresh() {
    setState(() {
      // Released speech becomes editable text; it is never sent here.
      if (widget.controller.text.isNotEmpty) _typing = true;
    });
  }

  void _typeMessage() {
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 63),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(32),
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
          asset: AssistantAssets.photo,
          onPressed: widget.onPhotoPressed,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _typing || widget.waiting
              ? TextField(
                  key: const Key('assistant-message-field'),
                  controller: widget.controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
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
              : widget.voiceButtonBuilder(true),
        ),
        if (_typing || widget.waiting)
          widget.voiceButtonBuilder(false)
        else
          _ComposerButton(
            tooltip: 'Type a message',
            asset: AssistantAssets.keyboard,
            onPressed: widget.enabled ? _typeMessage : null,
          ),
        if (_typing || widget.waiting || widget.hasImages)
          _ComposerButton(
            tooltip: 'Send message',
            asset: AssistantAssets.send,
            onPressed: widget.onSendPressed,
          ),
      ],
    ),
  );
}

class _ComposerButton extends StatelessWidget {
  const _ComposerButton({
    required this.tooltip,
    required this.asset,
    required this.onPressed,
  });

  final String tooltip, asset;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(width: 38, height: 42),
    padding: const EdgeInsets.all(5),
    icon: Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Image.asset(asset, width: 28, height: 24, fit: BoxFit.contain),
    ),
  );
}
