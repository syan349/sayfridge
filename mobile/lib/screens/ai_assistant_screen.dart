import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_bottom_navigation.dart';
import '../widgets/app_page_footer.dart';
import '../widgets/assistant_widgets.dart';
import 'camera_input_screen.dart';
import 'conversation_history_screen.dart';
import 'agent_conversation_screen.dart';
import '../state/agent_controller.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({
    this.isGuest = false,
    this.onHomeTap,
    this.onProfileTap,
    this.onLoginTap,
    this.agentController,
    super.key,
  });

  final bool isGuest;
  final VoidCallback? onHomeTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onLoginTap;
  final AgentController? agentController;

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
        onHomeTap: widget.onHomeTap,
        onProfileTap: widget.onProfileTap,
      );
    }
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: widget.isGuest
                  ? Column(
                      children: [
                        Expanded(child: _buildScrollableContent()),
                        AppPageFooter(
                          action: GuestLoginButton(
                            onPressed:
                                widget.onLoginTap ??
                                () => Navigator.of(context).maybePop(),
                          ),
                          showLoginHint: true,
                          selectedDestination:
                              AppNavigationDestination.assistant,
                          onHomeTap:
                              widget.onHomeTap ??
                              () => Navigator.of(context).maybePop(),
                          onProfileTap: widget.onProfileTap,
                        ),
                      ],
                    )
                  : Stack(
                      children: [
                        Positioned.fill(child: _buildScrollableContent()),
                        if (!widget.isGuest)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 255,
                            child: const IgnorePointer(
                              child: _BottomListMask(),
                            ),
                          ),
                        if (!widget.isGuest)
                          Positioned(
                            left: 22,
                            right: 22,
                            bottom: 116,
                            child: AssistantComposer(
                              controller: _messageController,
                              onPhotoPressed: _openCamera,
                              onSendPressed: _showExpiryResults,
                            ),
                          ),
                        Positioned(
                          left: 35,
                          right: 35,
                          bottom: 4,
                          child: AppBottomNavigation(
                            onHomeTap:
                                widget.onHomeTap ??
                                () => Navigator.of(context).maybePop(),
                            onProfileTap: widget.onProfileTap,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableContent() {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(25, 27, 25, widget.isGuest ? 0 : 238),
      children: [
        AssistantHeader(
          onNewConversation: _startNewConversation,
          onHistory: _openHistory,
        ),
        const SizedBox(height: 15),
        const Center(
          child: Text(
            'Add information using voice, photos, or text.',
            style: TextStyle(color: AppColors.muted, fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 18),
        const AssistantGreeting(),
        if (widget.isGuest)
          _buildGuestContent()
        else if (_showResults)
          _buildResultsContent()
        else
          _buildEmptyContent(),
      ],
    );
  }

  Widget _buildEmptyContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 45),
        const Center(
          child: Text(
            'Manage your inventory\nin one conversation',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              height: 1.12,
            ),
          ),
        ),
        const SizedBox(height: 25),
        const Center(
          child: Text(
            'Tell me what you bought, used, moved,\nor want to check..',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 16.5,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 35),
        const Text(
          'Try saying',
          style: TextStyle(color: Color(0xFF707070), fontSize: 16),
        ),
        const SizedBox(height: 11),
        AssistantSuggestionTile(
          label: 'I want to update my inventory',
          asset: AssistantAssets.update,
          onTap: () => _showExpiryResults('What’s expiring soon?'),
        ),
        const SizedBox(height: 14),
        AssistantSuggestionTile(
          label: 'Add items to my inventory',
          asset: AssistantAssets.add,
          onTap: () => _showExpiryResults('Add items to my inventory'),
        ),
        const SizedBox(height: 14),
        AssistantSuggestionTile(
          label: 'Show me an inventory report',
          asset: AssistantAssets.report,
          onTap: () => _showExpiryResults('Show me an inventory report'),
        ),
      ],
    );
  }

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
        const SizedBox(height: 28),
        const Text(
          'Your inventory, organised\nwith a conversation.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.18,
          ),
        ),
        const SizedBox(height: 25),
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
    return Row(
      children: [
        ClipOval(
          child: Image.asset(
            AssistantAssets.aiAssistant,
            width: 42,
            height: 42,
            fit: BoxFit.cover,
            cacheWidth: 100,
          ),
        ),
        const SizedBox(width: 11),
        const Flexible(
          child: AssistantMessageBubble(
            message: 'I’ll organise that for you.',
            textStyle: exampleMessageStyle,
          ),
        ),
      ],
    );
  }
}

class _BottomListMask extends StatelessWidget {
  const _BottomListMask();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: 0),
            AppColors.background.withValues(alpha: 0.44),
            const Color(0xE8ECF8DF),
            const Color(0xFFF1F9E8),
          ],
          stops: const [0, 0.32, 0.66, 1],
        ),
      ),
    );
  }
}
