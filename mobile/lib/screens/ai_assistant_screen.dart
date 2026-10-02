import 'package:flutter/material.dart';

import '../models/agent_input_draft.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_page_footer.dart';
import '../widgets/assistant_widgets.dart';
import '../widgets/assistant_welcome.dart';
import '../widgets/assistant_scroll_layout.dart';
import 'camera_input_screen.dart';
import 'conversation_history_screen.dart';
import 'agent_conversation_screen.dart';
import '../state/agent_controller.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({
    this.isGuest = false,
    this.onLoginTap,
    this.agentController,
    this.displayName,
    this.initialDraft,
    super.key,
  });

  final bool isGuest;
  final VoidCallback? onLoginTap;
  final AgentController? agentController;
  final String? displayName;
  final AgentInputDraft? initialDraft;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  static const _inventoryRoot = 'assets/icons/inventory';

  static const _expiringItems = <InventoryItemData>[
    InventoryItemData(
      name: 'Chicken Thigh',
      quantity: '500g',
      location: 'Fridge',
      daysLeft: '1 day left',
      imageAsset: '$_inventoryRoot/chicken_drumstick.png',
      quantityIsEstimate: true,
      expiryIsEstimate: true,
    ),
    InventoryItemData(
      name: 'Salmon Fillet',
      quantity: '750g',
      location: 'Fridge',
      daysLeft: '1 day left',
      imageAsset: '$_inventoryRoot/salmon_fillet.png',
    ),
    InventoryItemData(
      name: 'Tomatoes',
      quantity: '3 pcs',
      location: 'Pantry',
      daysLeft: '2 day left',
      imageAsset: '$_inventoryRoot/tomato.png',
    ),
    InventoryItemData(
      name: 'Milk',
      quantity: '300ml',
      location: 'Fridge',
      daysLeft: '2 day left',
      imageAsset: '$_inventoryRoot/milk.png',
      quantityIsEstimate: true,
      expiryIsEstimate: true,
    ),
    InventoryItemData(
      name: 'Beef tenderloin',
      quantity: '450g',
      location: 'Freezer',
      daysLeft: '3 day left',
      imageAsset: '$_inventoryRoot/beef_tenderloin.png',
      expiryIsEstimate: true,
    ),
    InventoryItemData(
      name: 'Bacon',
      quantity: '400g',
      location: 'Fridge',
      daysLeft: '3 day left',
      imageAsset: '$_inventoryRoot/bacon.png',
      quantityIsEstimate: true,
    ),
  ];

  final _messageController = TextEditingController();
  bool _showResults = false;
  String _sentMessage = 'What’s expiring soon?';

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _startNewConversation() {
    FocusScope.of(context).unfocus();
    _messageController.clear();
    setState(() => _showResults = false);
  }

  void _showExpiryResults([String? message]) {
    FocusScope.of(context).unfocus();
    final value = (message ?? _messageController.text).trim();
    setState(() {
      _sentMessage = value.isEmpty ? 'What’s expiring soon?' : value;
      _showResults = true;
      _messageController.clear();
    });
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ConversationHistoryScreen(),
      ),
    );
  }

  void _openCamera() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CameraInputScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isGuest && widget.agentController != null) {
      return AgentConversationScreen(
        controller: widget.agentController!,
        displayName: widget.displayName,
        initialDraft: widget.initialDraft,
      );
    }
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom == 0
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AssistantScrollLayout(
                bottomInset: bottomInset,
                header: Padding(
                  padding: const EdgeInsets.fromLTRB(25, 27, 25, 15),
                  child: AssistantHeader(
                    onNewConversation: _startNewConversation,
                    onHistory: _openHistory,
                  ),
                ),
                contentBuilder: (context, bottomPadding) =>
                    _buildScrollableContent(bottomPadding),
                footer: widget.isGuest
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(25, 14, 25, 28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Log in to start your own inventory.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 17),
                            GuestLoginButton(
                              key: const Key('assistant-bottom-action'),
                              onPressed:
                                  widget.onLoginTap ??
                                  () => Navigator.of(context).maybePop(),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(25, 8, 25, 28),
                            child: AssistantComposer(
                              key: const Key('assistant-bottom-action'),
                              controller: _messageController,
                              onPhotoPressed: _openCamera,
                              onSendPressed: _showExpiryResults,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableContent(double bottomPadding) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(25, 0, 25, bottomPadding),
      children: [
        const Center(
          child: Text(
            'Add information using voice, photos, or text.',
            style: TextStyle(color: AppColors.muted, fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 18),
        AssistantGreeting(
          message: widget.isGuest
              ? 'Hey! How can I help you?'
              : 'Hey, Tim!  How can I help you?',
        ),
        if (widget.isGuest)
          _buildGuestContent()
        else if (_showResults)
          _buildResultsContent()
        else
          _buildEmptyContent(),
      ],
    );
  }

  Widget _buildEmptyContent() => AssistantWelcome(
    onSuggestionSelected: (message) => _showExpiryResults(
      message == 'I want to update my inventory'
          ? 'What’s expiring soon?'
          : message,
    ),
  );

  Widget _buildResultsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 35),
        UserMessageBubble(message: _sentMessage),
        const SizedBox(height: 38),
        const Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '6 items',
                style: TextStyle(
                  color: inventoryEstimatedColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(text: ' expire in the next 3 days.'),
            ],
          ),
          style: TextStyle(fontSize: 19, height: 1.2),
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            _ValueLegendItem(label: 'Exact', color: inventoryExactColor),
            SizedBox(width: 25),
            _ValueLegendItem(
              label: 'AI - Estimated',
              color: inventoryEstimatedColor,
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < _expiringItems.length; index++) ...[
          InventoryItemCard(item: _expiringItems[index]),
          if (index != _expiringItems.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildGuestContent() {
    const sampleItem = InventoryItemData(
      name: 'Tomatoes',
      quantity: '1 kg',
      location: 'Pantry',
      daysLeft: '7 day left',
      imageAsset: '$_inventoryRoot/tomato.png',
    );

    return Column(
      children: [
        const SizedBox(height: 40),
        const Text(
          'Your inventory, organised\nwith a conversation.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.18,
          ),
        ),
        const SizedBox(height: 40),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(17, 20, 17, 20),
          decoration: BoxDecoration(
            color: const Color(0x8CFFFFFF),
            border: Border.all(color: const Color(0xFFCBE3BA), width: 2),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EXAMPLE CONVERSATION',
                style: TextStyle(color: Color(0xFF666666), fontSize: 15),
              ),
              SizedBox(height: 18),
              UserMessageBubble(
                message: 'I bought 1 kg of tomatoes.',
                textStyle: exampleMessageStyle,
              ),
              SizedBox(height: 17),
              _GuestAssistantReply(),
              SizedBox(height: 18),
              InventoryItemCard(item: sampleItem, compact: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _ValueLegendItem extends StatelessWidget {
  const _ValueLegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF818181), fontSize: 15),
        ),
      ],
    );
  }
}

class _GuestAssistantReply extends StatelessWidget {
  const _GuestAssistantReply();

  @override
  Widget build(BuildContext context) {
    return const AssistantReply(
      avatarSize: 42,
      message: 'I’ll organise that for you.',
      textStyle: exampleMessageStyle,
    );
  }
}
