import 'package:flutter/material.dart';

import '../repositories/workspace_repository.dart';
import '../services/api_exception.dart';

/// A dialog owns its controllers until its route is disposed (including exit animation).
class BusinessField {
  const BusinessField(
    this.keyName,
    this.label, {
    this.initial = '',
    this.options,
    this.validator,
    this.readOnly = false,
  });
  final String keyName, label, initial;
  final Map<String, String>? options;
  final String? Function(String?)? validator;
  final bool readOnly;
}

Future<bool?> businessForm(
  BuildContext context, {
  required String title,
  required List<BusinessField> fields,
  required Future<void> Function(Map<String, String>) submit,
  String? explanation,
  bool idempotentRetry = false,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _BusinessForm(
    title: title,
    fields: fields,
    submit: submit,
    explanation: explanation,
    idempotentRetry: idempotentRetry,
  ),
);

class _BusinessForm extends StatefulWidget {
  const _BusinessForm({
    required this.title,
    required this.fields,
    required this.submit,
    required this.idempotentRetry,
    this.explanation,
  });
  final String title;
  final List<BusinessField> fields;
  final Future<void> Function(Map<String, String>) submit;
  final bool idempotentRetry;
  final String? explanation;
  @override
  State<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends State<_BusinessForm> {
  final _form = GlobalKey<FormState>();
  late final _fields = {
    for (final f in widget.fields)
      f.keyName: TextEditingController(text: f.initial),
  };
  bool _busy = false, _uncertain = false, _conflict = false;
  String? _error;
  Map<String, String>? _frozen;

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final values =
        _frozen ??
        {for (final e in _fields.entries) e.key: e.value.text.trim()};
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(values);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uncertain =
            error is! ApiException ||
            error.statusCode == 0 ||
            error.statusCode >= 500;
        if (error is ApiException && error.code == 'INVALID_RESPONSE') {
          _uncertain = true;
        }
        _conflict = error is ApiException && error.isConflict;
        if (_uncertain) _frozen = values;
        _error =
            '${businessError(error)}${_uncertain ? '\nThe result may be unknown. ${widget.idempotentRetry ? 'Retry uses the same operation identity and inputs.' : 'Close and reload to check before submitting again.'}' : ''}${_conflict ? '\nClose and reload the latest state before editing again.' : ''}';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.explanation != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(widget.explanation!),
                ),
              for (final field in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: field.options == null
                      ? TextFormField(
                          controller: _fields[field.keyName],
                          enabled: !_busy,
                          readOnly: field.readOnly || _frozen != null,
                          decoration: InputDecoration(labelText: field.label),
                          validator: field.validator,
                        )
                      : DropdownButtonFormField<String>(
                          initialValue: _fields[field.keyName]!.text.isEmpty
                              ? null
                              : _fields[field.keyName]!.text,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: field.label),
                          items: field.options!.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _busy || _frozen != null
                              ? null
                              : (value) =>
                                    _fields[field.keyName]!.text = value ?? '',
                          validator: field.validator,
                        ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  key: const Key('business-error'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed:
              _busy || _conflict || (_uncertain && !widget.idempotentRetry)
              ? null
              : _submit,
          child: Text(
            _busy
                ? 'Saving…'
                : _uncertain
                ? 'Retry same operation'
                : 'Confirm',
          ),
        ),
      ],
    ),
  );
}

String? requiredValue(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;

const spaceTypes = {
  'FRIDGE': 'Fridge',
  'FREEZER': 'Freezer',
  'PANTRY': 'Pantry',
  'WAREHOUSE': 'Warehouse',
  'OTHER': 'Other',
};

Future<bool?> editSpace(
  BuildContext context,
  WorkspaceRepository workspace, {
  String? id,
  String name = '',
  String type = 'FRIDGE',
}) => businessForm(
  context,
  title: id == null ? 'Add storage space' : 'Edit storage space',
  fields: [
    BusinessField(
      'name',
      'Name',
      initial: name,
      validator: (value) =>
          requiredValue(value) ??
          (value!.trim().length > 100 ? 'Maximum 100 characters' : null),
    ),
    BusinessField(
      'type',
      'Type',
      initial: type,
      options: spaceTypes,
      validator: requiredValue,
    ),
  ],
  submit: (values) async {
    await workspace.saveSpace(values, id: id);
  },
);
