import 'package:flutter/material.dart';

import 'app_bottom_navigation.dart';

/// Presentation for the shared text, photo and voice input panel.
class AgentComposer extends StatefulWidget {
  const AgentComposer({
    required this.controller,
    required this.enabled,
    required this.hasImages,
    required this.onPhotoPressed,
    required this.onSendPressed,
    required this.voiceButton,
    this.voiceModeReset = 0,
    this.waiting = false,
    this.voiceActive = false,
    this.maxLength = 8000,
    this.inputKey = const Key('assistant-message-field'),
    this.textTopPadding = 6,
    this.inline = false,
    this.hintText,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled, hasImages, waiting, voiceActive;
  final int voiceModeReset;
  final int maxLength;
  final Key inputKey;
  final double textTopPadding;
  final bool inline;
  final String? hintText;
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
    if (oldWidget.voiceModeReset != widget.voiceModeReset) {
      _typing = false;
      _focusNode.unfocus();
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

  Widget _assetIcon(String asset) =>
      Image.asset(asset, width: 24, height: 20, fit: BoxFit.contain);

  Widget _photoButton() => _ComposerButton(
    tooltip: 'Add photos',
    icon: _assetIcon(AssistantAssets.photo),
    onPressed: widget.voiceActive ? null : widget.onPhotoPressed,
  );

  Widget _sendButton() => _ComposerButton(
    tooltip: 'Send message',
    icon: _assetIcon(AssistantAssets.send),
    onPressed: widget.voiceActive ? null : widget.onSendPressed,
  );

  Widget _typingLayout() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        // Selection handles extend below the field; keep them clear of actions.
        padding: EdgeInsets.fromLTRB(
          8,
          widget.textTopPadding,
          8,
          24 - widget.textTopPadding,
        ),
        child: TextField(
          key: widget.inputKey,
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled && !widget.voiceActive,
          maxLines: 6,
          minLines: 1,
          maxLength: widget.maxLength,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: const TextStyle(fontSize: 16, height: 1.2),
          textAlign: TextAlign.left,
          decoration: InputDecoration(
            isCollapsed: true,
            contentPadding: EdgeInsets.zero,
            counterText: '',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            hintText: widget.waiting
                ? 'Answer the pending items above'
                : 'Send message ...',
            hintStyle: const TextStyle(color: Color(0xFFA4A4AE), fontSize: 16),
          ),
        ),
      ),
      Row(
        children: [
          _photoButton(),
          const Spacer(),
          _ComposerButton(
            tooltip: 'Switch to voice input',
            icon: _assetIcon(AssistantAssets.microphone),
            onPressed: widget.enabled && !widget.voiceActive
                ? _voiceMode
                : null,
          ),
          Container(
            width: 1,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            color: const Color(0xFFC6C6CB),
          ),
          _sendButton(),
        ],
      ),
    ],
  );

  Widget _inlineTypingLayout() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: TextField(
            key: widget.inputKey,
            controller: widget.controller,
            focusNode: _focusNode,
            enabled: widget.enabled && !widget.voiceActive,
            minLines: 1,
            maxLines: 4,
            maxLength: widget.maxLength,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 14, height: 1.35),
            decoration: InputDecoration(
              isCollapsed: true,
              counterText: '',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              hintText: widget.hintText,
              hintStyle: const TextStyle(color: Color(0xFFA4A4AE)),
            ),
          ),
        ),
      ),
      _ComposerButton(
        tooltip: 'Switch to voice input',
        icon: _assetIcon(AssistantAssets.microphone),
        onPressed: widget.enabled && !widget.voiceActive ? _voiceMode : null,
      ),
    ],
  );

  Widget _voiceLayout() => Row(
    children: [
      if (!widget.inline) _photoButton(),
      if (widget.hasImages) const SizedBox(width: 42),
      Expanded(child: widget.voiceButton),
      _ComposerButton(
        tooltip: 'Type a message',
        icon: _assetIcon(AssistantAssets.keyboard),
        onPressed: widget.enabled && !widget.voiceActive ? _typeMessage : null,
      ),
      if (widget.hasImages) _sendButton(),
    ],
  );

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: widget.inline ? 56 : 63),
    padding: EdgeInsets.symmetric(
      horizontal: widget.inline ? 8 : 12,
      vertical: widget.inline ? 5 : 8,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: const Color(0xFFE5E7E1)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 10,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: _typing || widget.waiting
        ? widget.inline
              ? _inlineTypingLayout()
              : _typingLayout()
        : _voiceLayout(),
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
    constraints: const BoxConstraints.tightFor(width: 42, height: 44),
    padding: const EdgeInsets.all(4),
    icon: Opacity(opacity: onPressed == null ? 0.4 : 1, child: icon),
  );
}
