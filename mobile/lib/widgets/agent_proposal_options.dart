import 'dart:convert';

import 'package:flutter/material.dart';

import '../repositories/workspace_repository.dart';
import '../services/voice_input_service.dart';
import 'agent_input_panel.dart';

typedef ProposalResponse = ({String? inventoryId, String? message});

/// Select real catalog/space/batch options, with text for details that cannot be
/// inferred. Answers use the existing item-scoped resume contract.
class AgentProposalOptions extends StatefulWidget {
  const AgentProposalOptions({
    required this.workspace,
    required this.details,
    required this.errorCode,
    required this.editing,
    required this.enabled,
    required this.onChanged,
    this.voiceInput,
    this.onMessage,
    super.key,
  });

  final WorkspaceRepository workspace;
  final Map<String, dynamic> details;
  final String? errorCode;
  final bool editing, enabled;
  final ValueChanged<ProposalResponse> onChanged;
  final VoiceInputService? voiceInput;
  final ValueChanged<String>? onMessage;

  @override
  State<AgentProposalOptions> createState() => _AgentProposalOptionsState();
}

class _AgentProposalOptionsState extends State<AgentProposalOptions> {
  final _text = TextEditingController();
  final _groups = <String, List<Map<String, dynamic>>>{};
  final _selected = <String, Map<String, dynamic>>{};
  final _failed = <String>{};
  bool _loading = false, _showText = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    final candidates = _maps(widget.details['candidates']);
    if (candidates.isNotEmpty) {
      _groups[candidates.first.containsKey('item_definition_name')
              ? 'batch'
              : 'space'] =
          candidates;
    }
    final categories = _maps(widget.details['categories']);
    if (categories.isNotEmpty) _groups['category'] = categories;
    final spaces = _maps(widget.details['spaces']);
    if (spaces.isNotEmpty) _groups['space'] = spaces;
    _loadOptions();
  }

  @override
  void dispose() {
    _text.removeListener(_changed);
    _text.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .where((row) => row['id'] is String)
            .toList()
      : [];

  Future<void> _loadOptions() async {
    final needed = <String, String>{
      if ((widget.editing || widget.errorCode == 'CATEGORY_REQUIRED') &&
          !_groups.containsKey('category'))
        'category': 'item-categories',
      if ((widget.editing || widget.errorCode == 'SPACE_REQUIRED') &&
          !_groups.containsKey('space'))
        'space': 'storage-spaces',
    };
    if (needed.isEmpty) return;
    setState(() => _loading = true);
    await Future.wait(
      needed.entries.map((entry) async {
        try {
          final options = await widget.workspace.choices(entry.value);
          if (!mounted) return;
          options.sort(
            (a, b) => (a['name'] as String).toLowerCase().compareTo(
              (b['name'] as String).toLowerCase(),
            ),
          );
          _groups[entry.key] = options;
          _failed.remove(entry.key);
        } catch (_) {
          if (mounted) _failed.add(entry.key);
        }
      }),
    );
    if (mounted) setState(() => _loading = false);
  }

  void _changed() {
    final parts = <String>[
      if (_selected['category'] case final category?)
        'Use category ${jsonEncode(category['name'])} (category_id: ${category['id']}).',
      if (_selected['space'] case final space?)
        'Use storage space ${jsonEncode(space['name'])} (storage_space_id: ${space['id']}).',
      if (_text.text.trim().isNotEmpty) _text.text.trim(),
    ];
    widget.onChanged((
      inventoryId: _selected['batch']?['id'] as String?,
      message: parts.isEmpty ? null : parts.join(' '),
    ));
  }

  String _label(String group, Map<String, dynamic> option) {
    if (group != 'batch') return option['name']?.toString() ?? 'Option';
    return '${option['item_definition_name'] ?? option['name'] ?? 'Batch'} · ${option['storage_space_name'] ?? ''} · ${option['confirmed_current_amount'] ?? option['display_amount'] ?? ''} ${option['confirmed_current_unit'] ?? option['display_unit'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final hasOptions = _groups.values.any((options) => options.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        for (final group in ['batch', 'category', 'space'])
          if (_groups[group]?.isNotEmpty ?? false) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Text(switch (group) {
                'batch' => 'Choose a batch',
                'category' => 'Choose a category',
                _ => 'Choose a storage space',
              }, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 224),
              child: SingleChildScrollView(
                child: group == 'batch'
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final option in _groups[group]!)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                ),
                                onPressed: widget.enabled
                                    ? () => _choose(group, option)
                                    : null,
                                child: Row(
                                  children: [
                                    Icon(
                                      _selected[group]?['id'] == option['id']
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(_label(group, option)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final option in _groups[group]!)
                            ChoiceChip(
                              key: ValueKey('proposal-$group-${option['id']}'),
                              label: Text(_label(group, option)),
                              selected: _selected[group]?['id'] == option['id'],
                              onSelected: widget.enabled
                                  ? (_) => _choose(group, option)
                                  : null,
                            ),
                        ],
                      ),
              ),
            ),
          ],
        if (_failed.isNotEmpty) ...[
          const Text('Some choices could not be loaded.'),
          TextButton(
            onPressed: widget.enabled && !_loading ? _loadOptions : null,
            child: const Text('Retry choices'),
          ),
        ],
        if (!_loading && !hasOptions || _showText) ...[
          const SizedBox(height: 8),
          AgentInputPanel(
            key: const Key('proposal-response-input'),
            inputKey: const Key('proposal-response-text'),
            controller: _text,
            enabled: widget.enabled,
            inline: true,
            voiceInput: widget.voiceInput,
            onMessage: widget.onMessage,
            maxLength: 1000,
            hintText: widget.editing
                ? 'Describe the change'
                : 'Enter the missing details',
          ),
        ] else if (hasOptions)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.enabled
                  ? () => setState(() => _showText = true)
                  : null,
              child: const Text('Describe another detail'),
            ),
          ),
      ],
    );
  }

  void _choose(String group, Map<String, dynamic> option) {
    setState(() {
      if (_selected[group]?['id'] == option['id']) {
        _selected.remove(group);
      } else {
        _selected[group] = option;
      }
    });
    _changed();
  }
}
