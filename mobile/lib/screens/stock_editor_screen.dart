import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../repositories/workspace_repository.dart';
import '../services/api_exception.dart';
import '../widgets/app_background.dart';
import '../widgets/business_forms.dart';
import '../widgets/inventory_visuals.dart';

class StockEditorScreen extends StatefulWidget {
  const StockEditorScreen({required this.workspace, this.item, super.key});
  final WorkspaceRepository workspace;
  final InventoryItem? item;
  @override
  State<StockEditorScreen> createState() => _StockEditorScreenState();
}

class _StockEditorScreenState extends State<StockEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(), _unit = TextEditingController();
  final _purchase = TextEditingController(),
      _expiry = TextEditingController(),
      _notes = TextEditingController();
  List<Map<String, dynamic>> _spaces = [], _definitions = [];
  String? _space, _definition, _error;
  bool _loading = true, _busy = false, _blocked = false;
  bool _loadingDefinitionChoices = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _space = item?.storageSpaceId;
    _definition = item?.itemDefinitionId;
    _purchase.text = dateInput(item?.purchaseDate);
    _expiry.text = dateInput(item?.expiryDate);
    _notes.text = item?.notes ?? '';
    _load();
  }

  @override
  void dispose() {
    for (final field in [_amount, _unit, _purchase, _expiry, _notes]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final spaces = await widget.workspace.choices('storage-spaces');
      final definitions = widget.item == null
          ? await widget.workspace.choices('item-definitions')
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      final item = widget.item;
      if (item != null && !spaces.any((s) => s['id'] == item.storageSpaceId)) {
        spaces.insert(0, {
          'id': item.storageSpaceId,
          'name': '${item.storageSpaceName} (current)',
        });
      }
      setState(() {
        _spaces = spaces;
        _definitions = definitions;
        if (item == null) {
          if (!spaces.any((s) => s['id'] == _space)) _space = null;
          if (!definitions.any((d) => d['id'] == _definition)) {
            _definition = null;
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = businessError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newDefinition() async {
    setState(() {
      _busy = true;
      _loadingDefinitionChoices = true;
    });
    try {
      final categories = await widget.workspace.choices('item-categories');
      if (!mounted) return;
      if (categories.isEmpty) {
        setState(
          () => _error =
              'No active categories. Ask the backend team to prepare categories first.',
        );
        return;
      }
      Map<String, dynamic>? created;
      await businessForm(
        context,
        title: 'New private item definition',
        explanation: 'This creates an item name in your catalog, not stock.',
        fields: [
          BusinessField('name', 'Item name', validator: requiredValue),
          BusinessField(
            'category',
            'Category',
            validator: requiredValue,
            options: {
              for (final c in categories)
                c['id'] as String: c['name'] as String,
            },
          ),
        ],
        submit: (values) async {
          created = await widget.workspace.createDefinition(
            values['name']!,
            values['category']!,
          );
        },
      );
      if (!mounted) return;
      await _load();
      if (mounted &&
          created != null &&
          _definitions.any((d) => d['id'] == created!['id'])) {
        setState(() => _definition = created!['id'] as String);
      }
    } catch (e) {
      if (mounted) setState(() => _error = businessError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadingDefinitionChoices = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _blocked || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final item = widget.item;
    final values = <String, dynamic>{
      'storage_space_id': _space,
      'purchase_date': _purchase.text.trim().isEmpty
          ? null
          : _purchase.text.trim(),
      'expiry_date': _expiry.text.trim().isEmpty ? null : _expiry.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };
    try {
      if (item == null) {
        await widget.workspace.createStock({
          ...values,
          'item_definition_id': _definition,
          'amount': _amount.text.trim(),
          'unit': _unit.text.trim(),
        });
      } else {
        final before = {
          'storage_space_id': item.storageSpaceId,
          'purchase_date': item.purchaseDate == null
              ? null
              : dateInput(item.purchaseDate),
          'expiry_date': item.expiryDate == null
              ? null
              : dateInput(item.expiryDate),
          'notes': item.notes,
        };
        values.removeWhere((key, value) => before[key] == value);
        if (values.isNotEmpty) await widget.workspace.updateItem(item, values);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _blocked =
            e is! ApiException ||
            e.statusCode == 0 ||
            e.statusCode >= 500 ||
            e.code == 'INVALID_RESPONSE' ||
            e.isConflict;
        _error =
            '${businessError(e)}${_blocked ? '\nReturn to inventory and reload before trying again. A lost response does not prove that nothing was saved.' : ''}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  OverviewHeader(
                    title: widget.item == null ? 'Add inventory' : 'Edit item',
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : Form(
                            key: _form,
                            child: ListView(
                              padding: const EdgeInsets.all(25),
                              children: [
                                if (_error != null) ...[
                                  Text(
                                    _error!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                  if (!_blocked)
                                    TextButton(
                                      onPressed: _busy ? null : _load,
                                      child: const Text('Reload choices'),
                                    ),
                                ],
                                if (widget.item == null) ...[
                                  _select(
                                    'Item',
                                    _definition,
                                    _definitions,
                                    (v) => setState(() => _definition = v),
                                  ),
                                  TextButton(
                                    onPressed: _busy || _blocked
                                        ? null
                                        : _newDefinition,
                                    child: _loadingDefinitionChoices
                                        ? const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox.square(
                                                key: Key(
                                                  'definition-loading-indicator',
                                                ),
                                                dimension: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.2,
                                                    ),
                                              ),
                                              SizedBox(width: 10),
                                              Text('Loading categories…'),
                                            ],
                                          )
                                        : const Text(
                                            'Create a private item definition',
                                          ),
                                  ),
                                ] else ...[
                                  Text(
                                    widget.item!.itemDefinitionName,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Text(
                                    'Use Add / Use / Confirm remaining on item details to change quantities. This form changes dates, location and notes only.',
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                _select(
                                  'Storage space',
                                  _space,
                                  _spaces,
                                  (v) => setState(() => _space = v),
                                ),
                                TextButton(
                                  onPressed: _busy || _blocked
                                      ? null
                                      : () async {
                                          setState(() => _busy = true);
                                          await editSpace(
                                            context,
                                            widget.workspace,
                                          );
                                          if (!mounted) return;
                                          setState(() => _busy = false);
                                          await _load();
                                        },
                                  child: const Text('Add storage space'),
                                ),
                                if (widget.item == null) ...[
                                  _field(
                                    'Amount',
                                    _amount,
                                    (v) => validateAmount(v),
                                  ),
                                  _field(
                                    'Unit (e.g. kg, g, ml, pcs)',
                                    _unit,
                                    (v) =>
                                        requiredValue(v) ??
                                        (v!.length > 16
                                            ? 'Maximum 16 characters'
                                            : null),
                                  ),
                                ],
                                _field(
                                  'Purchase date (YYYY-MM-DD, optional)',
                                  _purchase,
                                  validateDate,
                                ),
                                _field(
                                  'Expiry date (YYYY-MM-DD, optional)',
                                  _expiry,
                                  validateDate,
                                ),
                                _field(
                                  'Notes (optional)',
                                  _notes,
                                  (v) => (v?.length ?? 0) > 1000
                                      ? 'Maximum 1000 characters'
                                      : null,
                                ),
                                const SizedBox(height: 24),
                                FilledButton(
                                  onPressed: _busy || _blocked ? null : _save,
                                  child: Text(
                                    _busy
                                        ? 'Saving…'
                                        : widget.item == null
                                        ? 'Add inventory'
                                        : 'Save changes',
                                  ),
                                ),
                              ],
                            ),
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

  Widget _field(
    String label,
    TextEditingController field,
    String? Function(String?) validator,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: field,
      enabled: !_busy && !_blocked,
      validator: validator,
      decoration: InputDecoration(labelText: label),
    ),
  );

  Widget _select(
    String label,
    String? selected,
    List<Map<String, dynamic>> items,
    ValueChanged<String?> onChange,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$selected:${items.length}'),
    initialValue: selected,
    isExpanded: true,
    validator: requiredValue,
    decoration: InputDecoration(labelText: label),
    items: items
        .map(
          (item) => DropdownMenuItem(
            value: item['id'] as String,
            child: Text(
              item['name'] as String,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: _busy || _blocked ? null : onChange,
  );
}
