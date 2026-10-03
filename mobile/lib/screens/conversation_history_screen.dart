import 'package:flutter/material.dart';

import '../widgets/page_scroll_fade.dart';

import '../state/agent_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/page_back_button.dart';

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
    return PageScrollFade(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(25, 27, 25, 42),
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                const PageBackButton(),
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
                const SizedBox(width: 48),
              ],
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Open a saved conversation to continue it. Recent chats and '
            'unfinished requests are kept on this device.',
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
          ] else if (agent == null || agent.history.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 45),
                child: Column(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 58,
                      color: AppColors.muted,
                    ),
                    SizedBox(height: 18),
                    Text(
                      'No current conversation',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
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
          const SizedBox(height: 32),
          const Text(
            'Earlier conversations',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 17),
          if (agent == null || agent.history.isEmpty)
            const Text(
              'No earlier conversations on this device yet.',
              style: TextStyle(color: AppColors.muted, fontSize: 15),
            )
          else
            for (final conversation in agent.history) ...[
              Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0xFFB5CE9F), width: 1.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  onTap: agent.canSend
                      ? () async {
                          await agent.openConversation(conversation.id);
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      : null,
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
                                conversation.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16.5),
                              ),
                              if (conversation.needsAttention) ...[
                                const SizedBox(height: 6),
                                Text(
                                  conversation.status == 'WAITING_INPUT' &&
                                          conversation.pendingRequest == null
                                      ? 'Waiting for your input'
                                      : 'Needs recovery',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 30),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          if (agent != null && agent.history.isNotEmpty && !agent.canSend)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Finish or recover the current request before switching conversations.',
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  String? _latestUserMessage(AgentController agent) {
    for (final entry in agent.messages.entries.toList().reversed) {
      if (entry.key.startsWith('user:')) return entry.value;
    }
    return null;
  }
}
