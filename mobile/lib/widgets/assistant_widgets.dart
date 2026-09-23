import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_bottom_navigation.dart';

const inventoryExactColor = Color(0xFF3F9E36);
const inventoryEstimatedColor = Color(0xFFE95A18);

class AssistantHeader extends StatelessWidget {
  const AssistantHeader({
    required this.onNewConversation,
    required this.onHistory,
    super.key,
  });

  final VoidCallback onNewConversation;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'AI Assistant',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
        ),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(color: Color(0x0F000000), blurRadius: 3),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderAction(
                tooltip: 'New conversation',
                onPressed: onNewConversation,
                child: Image.asset(
                  AssistantAssets.add,
                  width: 25,
                  height: 25,
                  cacheWidth: 80,
                ),
              ),
              const SizedBox(width: 15),
              _HeaderAction(
                tooltip: 'Conversation history',
                onPressed: onHistory,
                child: Image.asset(
                  AssistantAssets.history,
                  width: 25,
                  height: 25,
                  fit: BoxFit.contain,
                  cacheWidth: 80,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 23,
        child: SizedBox(width: 27, height: 34, child: Center(child: child)),
      ),
    );
  }
}

class AssistantGreeting extends StatelessWidget {
  const AssistantGreeting({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipOval(
          child: Image.asset(
            AssistantAssets.aiAssistant,
            width: 47,
            height: 47,
            fit: BoxFit.cover,
            cacheWidth: 120,
          ),
        ),
        const SizedBox(width: 11),
        Flexible(
          fit: FlexFit.loose,
          child: ClipPath(
            clipper: const _SpeechBubbleClipper(tailOnLeft: true),
            child: Container(
              height: 47,
              padding: const EdgeInsets.only(left: 25, right: 16),
              color: AppColors.primarySoft,
              child: const Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  'Hey, Tim!  How can I help you?',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class UserMessageBubble extends StatelessWidget {
  const UserMessageBubble({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ClipPath(
        clipper: const _SpeechBubbleClipper(tailOnLeft: false),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.fromLTRB(23, 13, 25, 13),
          color: AppColors.primarySoft,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _SpeechBubbleClipper extends CustomClipper<Path> {
  const _SpeechBubbleClipper({required this.tailOnLeft});

  final bool tailOnLeft;

  @override
  Path getClip(Size size) {
    const radius = 14.0;
    const tail = 13.0;
    final bodyLeft = tailOnLeft ? tail : 0.0;
    final bodyRight = tailOnLeft ? size.width : size.width - tail;
    final centerY = size.height / 2;

    // Draw the body and tail as one continuous outline. Keeping them in a
    // single subpath avoids an anti-aliased seam where two clipped shapes meet.
    final path = Path()..moveTo(bodyLeft + radius, 0);
    path
      ..lineTo(bodyRight - radius, 0)
      ..quadraticBezierTo(bodyRight, 0, bodyRight, radius);

    if (tailOnLeft) {
      path
        ..lineTo(bodyRight, size.height - radius)
        ..quadraticBezierTo(
          bodyRight,
          size.height,
          bodyRight - radius,
          size.height,
        )
        ..lineTo(bodyLeft + radius, size.height)
        ..quadraticBezierTo(
          bodyLeft,
          size.height,
          bodyLeft,
          size.height - radius,
        )
        ..lineTo(bodyLeft, centerY + 9)
        ..lineTo(0, centerY)
        ..lineTo(bodyLeft, centerY - 9)
        ..lineTo(bodyLeft, radius)
        ..quadraticBezierTo(bodyLeft, 0, bodyLeft + radius, 0);
    } else {
      path
        ..lineTo(bodyRight, centerY - 9)
        ..lineTo(size.width, centerY)
        ..lineTo(bodyRight, centerY + 9)
        ..lineTo(bodyRight, size.height - radius)
        ..quadraticBezierTo(
          bodyRight,
          size.height,
          bodyRight - radius,
          size.height,
        )
        ..lineTo(bodyLeft + radius, size.height)
        ..quadraticBezierTo(
          bodyLeft,
          size.height,
          bodyLeft,
          size.height - radius,
        )
        ..lineTo(bodyLeft, radius)
        ..quadraticBezierTo(bodyLeft, 0, bodyLeft + radius, 0);
    }
    return path..close();
  }

  @override
  bool shouldReclip(covariant _SpeechBubbleClipper oldClipper) {
    return tailOnLeft != oldClipper.tailOnLeft;
  }
}

class AssistantSuggestionTile extends StatelessWidget {
  const AssistantSuggestionTile({
    required this.label,
    required this.asset,
    required this.onTap,
    super.key,
  });

  final String label;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB3FFFFFF),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCAE2B7), width: 1.4),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Image.asset(asset, width: 24, height: 24, cacheWidth: 72),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 15.5, height: 1.1),
                ),
              ),
              const Icon(Icons.chevron_right, size: 27),
            ],
          ),
        ),
      ),
    );
  }
}

class InventoryItemData {
  const InventoryItemData({
    required this.name,
    required this.quantity,
    required this.location,
    required this.daysLeft,
    required this.imageAsset,
    this.quantityIsEstimate = false,
    this.expiryIsEstimate = false,
  });

  final String name;
  final String quantity;
  final String location;
  final String daysLeft;
  final String imageAsset;
  final bool quantityIsEstimate;
  final bool expiryIsEstimate;
}

class InventoryItemCard extends StatelessWidget {
  const InventoryItemCard({
    required this.item,
    this.compact = false,
    super.key,
  });

  final InventoryItemData item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cardHeight = compact ? 89.0 : 92.0;
    final imageSize = compact ? 64.0 : 68.0;

    return Container(
      height: cardHeight,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: const Color(0xFFA8D37F), width: 1.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              item.imageAsset,
              width: imageSize,
              height: imageSize,
              fit: BoxFit.cover,
              cacheWidth: 180,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, color: const Color(0xFFACD18D)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, height: 1.05),
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${item.quantityIsEstimate ? '≈ ' : ''}${item.quantity}',
                          style: TextStyle(
                            color: item.quantityIsEstimate
                                ? inventoryEstimatedColor
                                : inventoryExactColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const TextSpan(
                          text: ' | ',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        TextSpan(
                          text: item.location,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            width: compact ? 100 : 112,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      AssistantAssets.warn,
                      width: 19,
                      height: 19,
                      fit: BoxFit.contain,
                      cacheWidth: 64,
                    ),
                    const SizedBox(width: 11),
                    Text(
                      item.daysLeft,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: item.expiryIsEstimate
                            ? inventoryEstimatedColor
                            : inventoryExactColor,
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                Transform.translate(
                  // Move the complete action as one unit. This preserves the
                  // natural label/icon gap while optically aligning its edge.
                  offset: const Offset(10, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: const Offset(4, 0),
                        child: const Text(
                          'View item',
                          style: TextStyle(fontSize: 13.5),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 22),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AssistantComposer extends StatefulWidget {
  const AssistantComposer({
    required this.controller,
    required this.onPhotoPressed,
    required this.onSendPressed,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onPhotoPressed;
  final VoidCallback onSendPressed;

  @override
  State<AssistantComposer> createState() => _AssistantComposerState();
}

class _AssistantComposerState extends State<AssistantComposer> {
  late final FocusNode _focusNode;

  bool get _isTyping =>
      _focusNode.hasFocus || widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant AssistantComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _switchToVoiceMode() {
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 63,
      padding: const EdgeInsets.symmetric(horizontal: 15),
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
          _ComposerImageButton(
            tooltip: 'Open camera',
            asset: AssistantAssets.photo,
            onTap: widget.onPhotoPressed,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: TextField(
              key: const Key('assistant-message-field'),
              controller: widget.controller,
              focusNode: _focusNode,
              onSubmitted: (_) => widget.onSendPressed(),
              textInputAction: TextInputAction.send,
              style: const TextStyle(fontSize: 16),
              decoration:
                  InputDecoration.collapsed(
                    hintText: _isTyping
                        ? 'Send message ...'
                        : 'Press and hold to speak',
                    hintStyle: const TextStyle(
                      color: Color(0xFFA4A4AE),
                      fontSize: 16,
                    ),
                  ).copyWith(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
            ),
          ),
          if (_isTyping) ...[
            _ComposerImageButton(
              tooltip: 'Voice input',
              asset: AssistantAssets.microphone,
              onTap: _switchToVoiceMode,
            ),
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: const Color(0xFFC6C6CB),
            ),
            _ComposerImageButton(
              tooltip: 'Send message',
              asset: AssistantAssets.send,
              onTap: widget.onSendPressed,
            ),
          ] else
            _ComposerImageButton(
              tooltip: 'Type a message',
              asset: AssistantAssets.keyboard,
              onTap: _focusNode.requestFocus,
            ),
        ],
      ),
    );
  }
}

class _ComposerImageButton extends StatelessWidget {
  const _ComposerImageButton({
    required this.tooltip,
    required this.asset,
    required this.onTap,
  });

  final String tooltip;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 23,
        child: SizedBox(
          width: 38,
          height: 42,
          child: Center(
            child: SizedBox(
              width: 28,
              height: 24,
              child: Image.asset(asset, fit: BoxFit.contain, cacheWidth: 96),
            ),
          ),
        ),
      ),
    );
  }
}
