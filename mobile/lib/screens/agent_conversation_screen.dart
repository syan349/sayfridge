import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/agent_input_draft.dart';
import '../models/agent_image.dart';
import '../services/voice_input_service.dart';
import '../state/agent_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_input_panel.dart';
import '../widgets/app_background.dart';
import '../widgets/assistant_widgets.dart';
import '../widgets/assistant_welcome.dart';
import '../widgets/assistant_scroll_layout.dart';
import '../widgets/inventory_visuals.dart';
import '../widgets/business_forms.dart';
import 'camera_input_screen.dart';
import 'conversation_history_screen.dart';

class AgentConversationScreen extends StatefulWidget {
  const AgentConversationScreen({
    required this.controller,
    this.pickImages,
    this.voiceInput,
    this.displayName,
    this.initialDraft,
    super.key,
  });
  final AgentController controller;
  final Future<List<XFile>> Function()? pickImages;
  final VoiceInputService? voiceInput;
  final String? displayName;
  final AgentInputDraft? initialDraft;
  @override
  State<AgentConversationScreen> createState() =>
      _AgentConversationScreenState();
}

class _AgentConversationScreenState extends State<AgentConversationScreen> {
  final _message = TextEditingController();
  final _footerKey = GlobalKey();
  int _inputReset = 0;

  @override
  void initState() {
    super.initState();
    _message.text = widget.initialDraft?.text ?? '';
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<bool> _send(AgentInputDraft draft) async {
    if (!widget.controller.canSend) return false;
    await widget.controller.send(draft.text, images: draft.images);
    return widget.controller.error == null;
  }

  void _messageFor(String text) {
    final footer = _footerKey.currentContext?.findRenderObject() as RenderBox?;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          (footer?.size.height ?? 100) +
              MediaQuery.paddingOf(context).bottom +
              12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom == 0
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;
    return Scaffold(
      body: Stack(
        children: [
          AppBackground(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) {
                      final agent = widget.controller;
                      final name = widget.displayName
                          ?.trim()
                          .split(RegExp(r'\s+'))
                          .first;
                      final showWelcome =
                          agent.messages.isEmpty &&
                          agent.items.isEmpty &&
                          !agent.waiting &&
                          !agent.unresolved &&
                          agent.error == null;
                      return AssistantScrollLayout(
                        bottomInset: bottomInset,
                        contentBuilder: (context, bottomPadding) => ListView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            25,
                            27,
                            25,
                            bottomPadding,
                          ),
                          children: [
                            AssistantHeader(
                              onNewConversation: () async {
                                if (agent.canSend) {
                                  await agent.newConversation();
                                  if (!mounted || agent.error != null) {
                                    return;
                                  }
                                  _message.clear();
                                  setState(() {
                                    _inputReset++;
                                  });
                                } else {
                                  _messageFor(
                                    'Resolve or cancel pending items, or recover the current request first.',
                                  );
                                }
                              },
                              onHistory: () async {
                                final previousId = agent.conversationId;
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ConversationHistoryScreen(
                                      controller: agent,
                                    ),
                                  ),
                                );
                                if (!mounted ||
                                    agent.conversationId == previousId) {
                                  return;
                                }
                                _message.clear();
                                setState(() {
                                  _inputReset++;
                                });
                              },
                            ),
                            const SizedBox(height: 15),
                            const Center(
                              child: Text(
                                'Add information using voice, photos, or text.',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            AssistantGreeting(
                              message: name == null || name.isEmpty
                                  ? 'Hey! How can I help you?'
                                  : 'Hey, $name! How can I help you?',
                            ),
                            if (showWelcome)
                              AssistantWelcome(
                                onSuggestionSelected: agent.canSend
                                    ? (message) => agent.send(message)
                                    : null,
                              )
                            else
                              const SizedBox(height: 24),
                            for (final message in agent.messages.entries)
                              if (message.value.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  child: message.key.startsWith('user:')
                                      ? UserMessageBubble(
                                          message: message.value,
                                          textStyle: exampleMessageStyle,
                                        )
                                      : AssistantReply(
                                          textStyle: exampleMessageStyle,
                                          message: message.value,
                                        ),
                                ),
                            for (final item in agent.items)
                              _AgentItemCard(
                                controller: agent,
                                item: item,
                                pickImages: widget.pickImages,
                              ),
                            if (agent.waiting)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'Waiting for your input. Pending actions have not all completed.',
                                  style: TextStyle(
                                    color: Color(0xFF667456),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
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
                                    onPressed: agent.busy
                                        ? null
                                        : agent.recover,
                                    child: const Text(
                                      'Check conversation state',
                                    ),
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
                        footer: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              key: _footerKey,
                              padding: const EdgeInsets.fromLTRB(25, 8, 25, 28),
                              child: AgentInputPanel(
                                controller: _message,
                                enabled: agent.canSend,
                                waiting: agent.waiting,
                                reset: _inputReset,
                                voiceInput: widget.voiceInput,
                                pickImages: widget.pickImages,
                                initialImages:
                                    widget.initialDraft?.images ?? const [],
                                submitOnMount: widget.initialDraft != null,
                                onMessage: _messageFor,
                                onSend: _send,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentItemCard extends StatelessWidget {
  const _AgentItemCard({
    required this.controller,
    required this.item,
    this.pickImages,
  });
  final AgentController controller;
  final Map<String, dynamic> item;
  final Future<List<XFile>> Function()? pickImages;

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

  Future<void> _supportPhoto(BuildContext context) async {
    try {
      late final List<XFile> files;
      if (pickImages != null) {
        files = await pickImages!.call();
      } else {
        final selected = await Navigator.of(context).push<List<XFile>>(
          MaterialPageRoute<List<XFile>>(
            builder: (_) => const CameraInputScreen(),
          ),
        );
        files = selected ?? [];
      }
      if (!context.mounted || files.isEmpty) return;
      final images = <AgentImage>[];
      for (final file in files.take(AgentImage.maxImages)) {
        final image = AgentImage.fromPickedBytes(await file.readAsBytes());
        image.validateDimensions();
        images.add(image);
      }
      AgentImage.validateBatch(images);
      await controller.respond(item, 'answer', images: images);
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to attach that photo.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = item['status'];
    final preview = _asMap(item['preview']);
    final draft = _asMap(preview?['draft']);
    final after = _asMap(preview?['after']);
    final previewDisplay = _asMap(preview?['display']);
    final itemDisplay = _asMap(item['display']);
    final display = previewDisplay == null && itemDisplay == null
        ? null
        : <String, dynamic>{...?previewDisplay, ...?itemDisplay};
    final error = item['error'] as Map<String, dynamic>?;
    final details = error?['details'] as Map<String, dynamic>?;
    final candidates = details?['candidates'] as List? ?? [];
    final uncertain = error?['code'] == 'EXECUTION_UNCERTAIN';
    final waiting = status == 'NEEDS_INPUT' || status == 'NEEDS_CONFIRMATION';
    final canRespond = controller.canRespond && waiting;
    final original = _text(item['original_text']);
    final heading =
        _text(display?['item_name']) ?? original ?? 'Inventory action';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0x70FFFFFF),
        border: Border.all(color: const Color(0xFFA8D589)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0879AF43),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9F7DF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.asset(
                      itemArtworkForName(heading),
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          heading,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Chip(
                          avatar: Icon(_statusIcon(status), size: 18),
                          label: Text(_statusLabel(status)),
                          labelStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          backgroundColor: _statusColor(status),
                          side: BorderSide.none,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFA8D589), height: 24),
              if (_text(display?['recognized_text']) case final recognized?)
                _DetailRow(label: 'Recognised text', value: recognized),
              if (_text(display?['category_name']) case final category?)
                _DetailRow(label: 'Category', value: category),
              if (_text(display?['space_name']) case final space?)
                _DetailRow(label: 'Location', value: space),
              if (_text(display?['package_description']) case final package?)
                _DetailRow(label: 'Package', value: package),
              if (_quantity(after, draft) case final quantity?)
                _DetailRow(label: 'Quantity', value: quantity),
              if (_text(draft?['purchase_date']) case final purchaseDate?)
                _DetailRow(label: 'Purchase date', value: purchaseDate),
              if (_text(draft?['expiry_date']) case final expiryDate?)
                _DetailRow(label: 'Expiry date', value: expiryDate),
              if (_stringList(display?['missing_fields']).isNotEmpty)
                _NoticeBox(
                  icon: Icons.help_outline,
                  title: 'Still needed',
                  values: _stringList(display?['missing_fields']),
                ),
              if (_stringList(display?['review_notes']).isNotEmpty)
                _NoticeBox(
                  icon: Icons.fact_check_outlined,
                  title: 'Review notes',
                  values: _stringList(display?['review_notes']),
                ),
              if (original != null)
                if (original != heading &&
                    original != _text(display?['recognized_text']))
                  _DetailRow(label: 'Original request', value: original),
              if (preview != null) ...[
                _DetailRow(
                  label: 'Calculation',
                  value: '${preview['calculation_method']}',
                ),
                if (preview['before'] is Map)
                  _DetailRow(
                    label: 'Before',
                    value: _balance(preview['before'] as Map),
                  ),
                if (preview['after'] is Map &&
                    _quantity(after, draft) !=
                        _balance(preview['after'] as Map))
                  _DetailRow(
                    label: 'After',
                    value: _balance(preview['after'] as Map),
                  ),
              ],
              if (error != null) Text('${error['message'] ?? error['code']}'),
              if (waiting) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
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
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(0, 40),
                        ),
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
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFA8D589)),
                          minimumSize: const Size(0, 40),
                          foregroundColor: AppColors.userMessage,
                        ),
                        onPressed: canRespond
                            ? () => _supportPhoto(context)
                            : null,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('Add supporting photo'),
                      ),
                    ],
                  ],
                ),
                if (!uncertain)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: canRespond
                          ? () => controller.respond(item, 'cancel')
                          : null,
                      child: const Text('Cancel item'),
                    ),
                  ),
              ],
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

  Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'null' ? null : text;
  }

  List<String> _stringList(Object? value) => value is List
      ? value
            .map((entry) => entry.toString())
            .where((entry) => entry.isNotEmpty)
            .toList()
      : const [];

  String? _quantity(Map<String, dynamic>? after, Map<String, dynamic>? draft) {
    final amount =
        after?['confirmed_current_amount'] ??
        after?['estimated_current_amount'] ??
        draft?['quantity_value'];
    final unit =
        after?['confirmed_current_unit'] ??
        after?['estimated_current_unit'] ??
        draft?['quantity_unit'];
    if (amount == null && unit == null) return null;
    final estimated = after?['estimated_current_amount'] != null;
    return '${estimated ? '≈ ' : ''}${amount ?? 'Unknown'} ${unit ?? ''}'
        .trim();
  }

  String _statusLabel(Object? status) => switch (status) {
    'NEEDS_INPUT' => 'Needs information',
    'NEEDS_CONFIRMATION' => 'Ready for review',
    'SUCCEEDED' => 'Added successfully',
    'FAILED' => 'Failed',
    'CANCELLED' => 'Cancelled',
    _ => status?.toString() ?? 'Pending',
  };

  IconData _statusIcon(Object? status) => switch (status) {
    'NEEDS_INPUT' => Icons.help_outline,
    'NEEDS_CONFIRMATION' => Icons.fact_check_outlined,
    'SUCCEEDED' => Icons.check_circle_outline,
    'FAILED' => Icons.error_outline,
    'CANCELLED' => Icons.cancel_outlined,
    _ => Icons.schedule,
  };

  Color _statusColor(Object? status) => switch (status) {
    'SUCCEEDED' => const Color(0xFFDDF4D0),
    'FAILED' => const Color(0xFFFFDDDD),
    'CANCELLED' => const Color(0xFFE6E6E6),
    'NEEDS_INPUT' => const Color(0xFFFFEBC2),
    _ => const Color(0xFFE9F5D9),
  };
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 94,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF77816D),
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 14, height: 1.4)),
        ),
      ],
    ),
  );
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({
    required this.icon,
    required this.title,
    required this.values,
  });

  final IconData icon;
  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF4DF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 8),
        Expanded(child: Text('$title: ${values.join(', ')}')),
      ],
    ),
  );
}
