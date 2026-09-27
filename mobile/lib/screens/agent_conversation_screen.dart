import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/agent_image.dart';
import '../state/agent_controller.dart';
import '../widgets/app_background.dart';
import '../widgets/app_bottom_navigation.dart';
import '../widgets/assistant_widgets.dart';
import '../widgets/business_forms.dart';
import 'camera_input_screen.dart';

class AgentConversationScreen extends StatefulWidget {
  const AgentConversationScreen({
    required this.controller,
    this.onHomeTap,
    this.onProfileTap,
    this.pickImages,
    super.key,
  });
  final AgentController controller;
  final VoidCallback? onHomeTap, onProfileTap;
  final Future<List<XFile>> Function()? pickImages;
  @override
  State<AgentConversationScreen> createState() =>
      _AgentConversationScreenState();
}

class _AgentConversationScreenState extends State<AgentConversationScreen> {
  final _message = TextEditingController();
  final List<AgentImage> _images = [];
  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!widget.controller.canSend ||
        (_message.text.trim().isEmpty && _images.isEmpty)) {
      return;
    }
    final text = _message.text;
    FocusScope.of(context).unfocus();
    await widget.controller.send(text, images: List.unmodifiable(_images));
    if (!mounted || widget.controller.error != null) return;
    _message.clear();
    setState(_images.clear);
  }

  Future<void> _pickImages() async {
    if (!widget.controller.canSend || _images.length >= AgentImage.maxImages) {
      return;
    }
    try {
      final selected = widget.pickImages != null
          ? await widget.pickImages!.call()
          : await _openCameraInput();
      if (!mounted || selected.isEmpty) return;
      final additions = <AgentImage>[];
      for (final file in selected.take(AgentImage.maxImages - _images.length)) {
        final bytes = await file.readAsBytes();
        final image = AgentImage.fromBytes(bytes, mimeType: _mimeType(file));
        await image.validateDimensions();
        additions.add(image);
      }
      AgentImage.validateBatch([..._images, ...additions]);
      if (!mounted) return;
      setState(() => _images.addAll(additions));
      if (selected.length > additions.length) {
        _messageFor('Send at most 4 images at a time.');
      }
    } on FormatException catch (e) {
      if (mounted) _messageFor(e.message);
    } catch (_) {
      if (mounted) {
        _messageFor('Unable to open those photos. Please try again.');
      }
    }
  }

  Future<List<XFile>> _openCameraInput() async {
    final selected = await Navigator.of(context).push<XFile>(
      MaterialPageRoute<XFile>(builder: (_) => const CameraInputScreen()),
    );
    return selected == null ? [] : [selected];
  }

  String _mimeType(XFile file) {
    final declared = file.mimeType?.toLowerCase();
    if (declared != null && declared.isNotEmpty) return declared;
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  void _messageFor(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
                            _AgentItemCard(
                              controller: agent,
                              item: item,
                              pickImages: widget.pickImages,
                            ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_images.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (
                                    var index = 0;
                                    index < _images.length;
                                    index++
                                  )
                                    _ImagePreview(
                                      key: ValueKey(
                                        'agent-image-${_images[index].imageId}',
                                      ),
                                      image: _images[index],
                                      onRemove: agent.canSend
                                          ? () => setState(
                                              () => _images.removeAt(index),
                                            )
                                          : null,
                                    ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              IconButton(
                                onPressed:
                                    agent.canSend &&
                                        _images.length < AgentImage.maxImages
                                    ? _pickImages
                                    : null,
                                tooltip: 'Add photos',
                                icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                ),
                              ),
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

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image, required this.onRemove, super.key});

  final AgentImage image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          image.bytes,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          semanticLabel: 'Selected photo',
        ),
      ),
      Positioned(
        right: -10,
        top: -10,
        child: IconButton.filled(
          onPressed: onRemove,
          tooltip: 'Remove photo',
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          padding: EdgeInsets.zero,
          iconSize: 17,
          icon: const Icon(Icons.close),
        ),
      ),
    ],
  );
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
        final selected = await Navigator.of(context).push<XFile>(
          MaterialPageRoute<XFile>(builder: (_) => const CameraInputScreen()),
        );
        files = selected == null ? [] : [selected];
      }
      if (!context.mounted || files.isEmpty) return;
      final file = files.first;
      final image = AgentImage.fromBytes(
        await file.readAsBytes(),
        mimeType: _agentImageMimeType(file),
      );
      await image.validateDimensions();
      await controller.respond(item, 'answer', images: [image]);
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              heading,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: Icon(_statusIcon(status), size: 18),
                label: Text(_statusLabel(status)),
                backgroundColor: _statusColor(status),
                side: BorderSide.none,
              ),
            ),
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
                    OutlinedButton.icon(
                      onPressed: canRespond
                          ? () => _supportPhoto(context)
                          : null,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Add supporting photo'),
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
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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

String _agentImageMimeType(XFile file) {
  final declared = file.mimeType?.toLowerCase();
  if (declared != null && declared.isNotEmpty) return declared;
  final name = file.name.toLowerCase();
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  return 'application/octet-stream';
}
