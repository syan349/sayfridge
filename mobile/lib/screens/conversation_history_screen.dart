import 'package:flutter/material.dart';

import '../state/agent_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';

class ConversationHistoryScreen extends StatelessWidget {
  const ConversationHistoryScreen({this.controller, super.key});

  final AgentController? controller;

  @override
  Widget build(BuildContext context) {
    final agent = controller;
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: agent == null
                  ? _content(context, null)
                  : ListenableBuilder(
                      listenable: agent,
                      builder: (context, _) => _content(context, agent),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AgentController? agent) {
    final hasCurrentConversation = agent?.conversationId != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 27, 24, 42),
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 29),
                  tooltip: 'Back',
                ),
              ),
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Conversation History',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.35,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
        ),
        const SizedBox(height: 30),
        const Text(
          'You can return to your current conversation here. Earlier '
          'conversations and full message history are not available yet.',
          style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 32),
        if (hasCurrentConversation) ...[
          const Text(
            'Current conversation',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 17),
          Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFB5CE9F), width: 1.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 11, 15),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded, size: 30),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _latestUserMessage(agent!) ??
                                'Return to your current session',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16.5),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            agent.waiting
                                ? 'Waiting for your input'
                                : agent.unresolved
                                ? 'Needs recovery'
                                : 'Open conversation',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 14.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 30),
                  ],
                ),
              ),
            ),
          ),
        ] else
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 45),
              child: Column(
                children: [
                  Icon(Icons.history_rounded, size: 58, color: AppColors.muted),
                  SizedBox(height: 18),
                  Text(
                    'No current conversation',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start a chat with the assistant to see it here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String? _latestUserMessage(AgentController agent) {
    for (final entry in agent.messages.entries.toList().reversed) {
      if (entry.key.startsWith('user:')) return entry.value;
    }
    return null;
  }
}
