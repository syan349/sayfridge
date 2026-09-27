import 'dart:convert';
import 'package:flutter/material.dart';

import '../state/agent_controller.dart';
import '../widgets/app_background.dart';
import '../widgets/app_bottom_navigation.dart';
import '../widgets/assistant_widgets.dart';
import '../widgets/business_forms.dart';

class AgentConversationScreen extends StatefulWidget {
  const AgentConversationScreen({
    required this.controller,
    this.onHomeTap,
    this.onProfileTap,
    super.key,
  });
  final AgentController controller;
  final VoidCallback? onHomeTap, onProfileTap;
  @override
  State<AgentConversationScreen> createState() =>
      _AgentConversationScreenState();
}

class _AgentConversationScreenState extends State<AgentConversationScreen> {
  final _message = TextEditingController();
  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _send() {
    if (!widget.controller.canSend || _message.text.trim().isEmpty) return;
    final text = _message.text;
    _message.clear();
    FocusScope.of(context).unfocus();
    widget.controller.send(text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final agent = widget.controller;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(25, 27, 25, 12),
                      child: AssistantHeader(
                        onNewConversation: () {
                          if (agent.canSend) {
                            agent.newConversation();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Resolve or cancel pending items, or recover the current request first.',
                                ),
                              ),
                            );
                          }
                        },
                        onHistory: () {
                          agent.recover();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Recovering the latest conversation. Full conversation history is not provided by the current API.',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 25,
                          vertical: 12,
                        ),
                        children: [
                          if (agent.messages.isEmpty &&
                              agent.items.isEmpty) ...[
                            const AssistantGreeting(
                              message: 'Hi! How can I help you?',
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Ask about your inventory or describe an action. Clear, exact actions may be applied immediately. Estimates and new spaces/items require confirmation.',
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: agent.canSend
                                  ? () => agent.send('What is expiring soon?')
                                  : null,
                              child: const Text('What is expiring soon?'),
                            ),
                          ],
                          for (final message in agent.messages.entries)
                            if (message.value.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: message.key.startsWith('user:')
                                    ? UserMessageBubble(
                                        message: message.value,
                                        textStyle: exampleMessageStyle,
                                      )
                                    : AssistantMessageBubble(
                                        textStyle: exampleMessageStyle,
                                        message: message.value,
                                      ),
                              ),
                          for (final item in agent.items)
                            _AgentItemCard(controller: agent, item: item),
                          if (agent.waiting)
                            const Text(
                              'Waiting for your input. Pending actions have not all completed.',
                            ),
                          if (agent.busy)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: LinearProgressIndicator(),
                            ),
                          if (agent.error != null)
                            Text(
                              agent.error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          if (agent.unresolved)
                            const Text(
                              'An earlier request is unresolved. Do not submit it as a new request.',
                            ),
                          if (agent.error != null || agent.unresolved)
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: agent.busy ? null : agent.recover,
                                  child: const Text('Check conversation state'),
                                ),
                                FilledButton(
                                  onPressed: agent.canRetry
                                      ? agent.retry
                                      : null,
                                  child: const Text('Retry same request'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(25, 8, 25, 22),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _message,
                              enabled: agent.canSend,
                              maxLines: 3,
                              minLines: 1,
                              maxLength: 8000,
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: agent.waiting
                                    ? 'Answer the pending items above'
                                    : 'Message your assistant…',
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          IconButton(
                            onPressed: agent.canSend ? _send : null,
                            tooltip: 'Send message',
                            icon: const Icon(Icons.send_outlined),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(35, 0, 35, 4),
                      child: AppBottomNavigation(
                        onHomeTap:
                            widget.onHomeTap ??
                            () => Navigator.of(context).maybePop(),
                        onProfileTap: widget.onProfileTap,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class _AgentItemCard extends StatelessWidget {
  const _AgentItemCard({required this.controller, required this.item});
  final AgentController controller;
  final Map<String, dynamic> item;

  Future<void> _answer(BuildContext context, String decision) async {
    await businessForm(
      context,
      title: decision == 'edit'
          ? 'Change this proposal'
          : 'Provide information',
      explanation: item['original_text'] as String?,
      fields: [
        BusinessField('message', 'Your response', validator: requiredValue),
      ],
      submit: (values) =>
          controller.respond(item, decision, message: values['message']),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = item['status'];
    final preview = item['preview'] as Map<String, dynamic>?;
    final error = item['error'] as Map<String, dynamic>?;
    final details = error?['details'] as Map<String, dynamic>?;
    final candidates = details?['candidates'] as List? ?? [];
    final uncertain = error?['code'] == 'EXECUTION_UNCERTAIN';
    final waiting = status == 'NEEDS_INPUT' || status == 'NEEDS_CONFIRMATION';
    final canRespond = controller.canRespond && waiting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item['original_text'] as String? ?? 'Inventory action',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Status: $status',
              style: TextStyle(
                color: status == 'SUCCEEDED' ? Colors.green : null,
              ),
            ),
            if (preview != null) ...[
              Text('Calculation: ${preview['calculation_method']}'),
              if (preview['before'] is Map)
                Text('Before: ${_balance(preview['before'] as Map)}'),
              if (preview['after'] is Map)
                Text('After: ${_balance(preview['after'] as Map)}'),
              ExpansionTile(
                title: const Text('Server proposal and estimate basis'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(preview),
                  ),
                ],
              ),
            ],
            if (error != null) Text('${error['message'] ?? error['code']}'),
            if (item['result'] != null)
              ExpansionTile(
                title: const Text('Actual server result'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(item['result']),
                  ),
                ],
              ),
            if (waiting)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (status == 'NEEDS_CONFIRMATION')
                    FilledButton(
                      onPressed: canRespond
                          ? () => controller.respond(item, 'confirm')
                          : null,
                      child: Text(
                        uncertain
                            ? 'Verify original action'
                            : 'Confirm proposal',
                      ),
                    ),
                  if (!uncertain) ...[
                    OutlinedButton(
                      onPressed: canRespond
                          ? () => _answer(
                              context,
                              status == 'NEEDS_INPUT' ? 'answer' : 'edit',
                            )
                          : null,
                      child: Text(
                        status == 'NEEDS_INPUT' ? 'Answer' : 'Edit proposal',
                      ),
                    ),
                    TextButton(
                      onPressed: canRespond
                          ? () => controller.respond(item, 'cancel')
                          : null,
                      child: const Text('Cancel item'),
                    ),
                  ],
                ],
              ),
            if (canRespond && !uncertain)
              for (final candidate in candidates)
                OutlinedButton(
                  onPressed: () => controller.respond(
                    item,
                    'answer',
                    selectedId: candidate['id'] as String,
                  ),
                  child: Text(
                    '${candidate['item_definition_name'] ?? candidate['name'] ?? candidate['id']} · ${candidate['storage_space_name'] ?? ''} · ${candidate['expiry_date'] ?? 'No expiry date'}',
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _balance(Map value) {
    final estimate =
        value['is_estimated'] == true ||
        value['estimated_current_amount'] != null;
    final amount =
        value['display_amount'] ??
        value['amount'] ??
        value['estimated_current_amount'] ??
        value['confirmed_current_amount'];
    final unit =
        value['display_unit'] ??
        value['unit'] ??
        value['estimated_current_unit'] ??
        value['confirmed_current_unit'];
    return '${estimate ? '≈ ' : ''}$amount $unit';
  }
}
