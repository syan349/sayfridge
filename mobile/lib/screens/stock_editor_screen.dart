import 'package:flutter/material.dart';

import '../widgets/page_scroll_fade.dart';

import '../models/inventory_item.dart';
import '../repositories/workspace_repository.dart';
import '../services/api_exception.dart';
import '../widgets/app_background.dart';
import '../widgets/business_forms.dart';
import '../widgets/inventory_visuals.dart';
import '../widgets/selection_field.dart';
import '../theme/app_theme.dart';

class StockEditorScreen extends StatefulWidget {
  const StockEditorScreen({required this.workspace, this.item, super.key});
  final WorkspaceRepository workspace;
  final InventoryItem? item;
  @override
  State<StockEditorScreen> createState() => _StockEditorScreenState();
}

class _StockEditorScreenState extends State<StockEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _estimated = false;
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
    _name.text = item?.itemDefinitionName ?? '';
    _estimated = item?.isEstimated ?? false;
    if (item != null) {
      _amount.text = _amountText(item.displayAmount);
      _unit.text = item.displayUnit;
    }
    _space = item?.storageSpaceId;
    _definition = item?.itemDefinitionId;
    _purchase.text = dateInput(item?.purchaseDate);
    _expiry.text = dateInput(item?.expiryDate);
    _notes.text = item?.notes ?? '';
    _load();
  }

  @override
  void dispose() {
    for (final field in [_name, _amount, _unit, _purchase, _expiry, _notes]) {
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
        if (_name.text.trim() != item.itemDefinitionName) {
          values['item_name'] = _name.text.trim();
        }
        final quantityChanged =
            !_estimated &&
            (double.tryParse(_amount.text.trim()) != item.displayAmount ||
                _unit.text.trim().toLowerCase() !=
                    item.displayUnit.toLowerCase());
        if (_estimated != item.isEstimated || quantityChanged) {
          values['quantity'] = _estimated
              ? {'mode': 'ESTIMATED'}
              : {
                  'mode': 'EXACT',
                  'amount': _amount.text.trim(),
                  'unit': _unit.text.trim(),
                };
        }
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
                    title: widget.item == null
                        ? 'Add inventory'
                        : 'Item details',
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : Theme(
                            data: Theme.of(context).copyWith(
                              inputDecorationTheme: Theme.of(context)
                                  .inputDecorationTheme
                                  .copyWith(
                                    fillColor: const Color(0x80FFFFFF),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(9),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFA8D589),
                                      ),
                                    ),
                                  ),
                            ),
                            child: Form(
                              key: _form,
                              child: PageScrollFade(
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    25,
                                    7,
                                    25,
                                    32,
                                  ),
                                  children: [
                                    if (_error != null) ...[
                                      Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                      if (!_blocked)
                                        TextButton(
                                          onPressed: _busy ? null : _load,
                                          child: const Text('Reload choices'),
                                        ),
                                      const SizedBox(height: 16),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: const Color(0xFFA8D589),
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        color: const Color(0x35FFFFFF),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: widget.item == null
                                            ? _newStockFields()
                                            : _itemFields(widget.item!),
                                      ),
                                    ),
                                    const SizedBox(height: 28),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: AppColors.text,
                                        minimumSize: const Size.fromHeight(54),
                                        textStyle: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      onPressed: _busy || _blocked
                                          ? null
                                          : _save,
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

  List<Widget> _newStockFields() => [
    _select(
      'Item',
      _definition,
      _definitions,
      (v) => setState(() => _definition = v),
    ),
    TextButton(
      onPressed: _busy || _blocked ? null : _newDefinition,
      child: _loadingDefinitionChoices
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  key: Key('definition-loading-indicator'),
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                SizedBox(width: 10),
                Flexible(child: Text('Loading categories…')),
              ],
            )
          : const Text('Create a private item definition'),
    ),
    const SizedBox(height: 8),
    _storageField(),
    _addSpaceButton(),
    const SizedBox(height: 8),
    _field('Amount', _amount, validateAmount),
    _field(
      'Unit (e.g. kg, g, ml, pcs)',
      _unit,
      (v) =>
          requiredValue(v) ?? (v!.length > 16 ? 'Maximum 16 characters' : null),
    ),
    _dateField('Purchase date (optional)', _purchase),
    const SizedBox(height: 18),
    _dateField('Expiry date (optional)', _expiry),
    const SizedBox(height: 18),
    _notesField(),
  ];

  List<Widget> _itemFields(InventoryItem item) => [
    Center(child: InventoryArtwork(item: item, size: 140)),
    const SizedBox(height: 24),
    _labelRow(
      'Item name',
      TextFormField(
        key: const Key('item-name-input'),
        controller: _name,
        enabled: !_busy && !_blocked,
        validator: (v) =>
            requiredValue(v) ??
            (v!.trim().length > 100 ? 'Maximum 100 characters' : null),
        decoration: const InputDecoration(),
      ),
    ),
    const SizedBox(height: 20),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label('Quantity'),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('item-quantity-input'),
                controller: _amount,
                enabled: !_busy && !_blocked,
                readOnly: _estimated,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) => validateAmount(v, allowZero: true),
                style: TextStyle(
                  fontSize: 16,
                  color: _estimated
                      ? const Color(0xFFD75A20)
                      : const Color(0xFF388D38),
                ),
                decoration: InputDecoration(
                  prefixText: _estimated ? '≈ ' : null,
                  prefixStyle: const TextStyle(
                    color: Color(0xFFD75A20),
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label('Unit'),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('item-unit-input'),
                controller: _unit,
                enabled: !_busy && !_blocked,
                readOnly: _estimated,
                validator: (v) =>
                    requiredValue(v) ??
                    (v!.trim().length > 16 ? 'Maximum 16 characters' : null),
                decoration: const InputDecoration(),
              ),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    Wrap(
      spacing: 14,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Type',
          style: TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        _quantityType('AI-estimate', _estimated, const Color(0xFFD75A20)),
        _quantityType('Exact', !_estimated, const Color(0xFF388D38)),
      ],
    ),
    const SizedBox(height: 8),
    const Text(
      'Choose Exact to enter a measured quantity. AI estimates are read-only.',
      style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
    ),
    const SizedBox(height: 22),
    _labelRow('Added on', _readOnlyValue(_displayDate(item.createdAt))),
    const SizedBox(height: 16),
    _labelRow('Purchase date', _dateField(null, _purchase)),
    const SizedBox(height: 16),
    _labelRow('Expiry date', _dateField(null, _expiry)),
    const SizedBox(height: 20),
    _labelRow('Storage space', _storageField(compact: true)),
    _addSpaceButton(),
    const SizedBox(height: 12),
    _notesField(),
  ];

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: Color(0xFF7D8278),
    ),
  );

  Widget _labelRow(String label, Widget field) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 270
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_label(label), const SizedBox(height: 8), field],
          )
        : Row(
            children: [
              Expanded(flex: 45, child: _label(label)),
              const SizedBox(width: 10),
              Expanded(flex: 55, child: field),
            ],
          ),
  );

  Widget _readOnlyValue(String value, {Color? color}) => InputDecorator(
    decoration: const InputDecoration(),
    child: Text(
      value,
      style: TextStyle(fontSize: 15, color: color),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );

  String _amountText(double amount) => amount == amount.truncateToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toString();

  Widget _quantityType(String label, bool active, Color color) => Semantics(
    selected: active,
    button: true,
    child: InkWell(
      onTap: _busy || _blocked
          ? null
          : () => setState(() {
              _estimated = label == 'AI-estimate';
              if (_estimated) {
                _amount.text = _amountText(widget.item!.displayAmount);
                _unit.text = widget.item!.displayUnit;
              }
            }),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: active ? color : AppColors.text,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: Color(0xFF7D8278)),
            ),
          ],
        ),
      ),
    ),
  );

  String _displayDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  Widget _dateField(
    String? label,
    TextEditingController controller,
  ) => TextFormField(
    controller: controller,
    enabled: !_busy && !_blocked,
    validator: validateDate,
    style: const TextStyle(fontSize: 15),
    decoration: InputDecoration(
      labelText: label,
      hintText: 'Not set',
      suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 40),
      suffixIcon: IconButton(
        tooltip:
            label ??
            (controller == _expiry
                ? 'Choose expiry date'
                : 'Choose purchase date'),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.calendar_today_outlined, size: 19),
        onPressed: _busy || _blocked
            ? null
            : () async {
                final current = DateTime.tryParse(controller.text);
                final date = await showDatePicker(
                  context: context,
                  initialDate: current ?? DateUtils.dateOnly(DateTime.now()),
                  firstDate: DateTime(
                    current != null && current.year < 1900
                        ? current.year
                        : 1900,
                  ),
                  lastDate: DateTime(
                    current != null && current.year > 2200
                        ? current.year
                        : 2200,
                    12,
                    31,
                  ),
                );
                if (mounted && date != null) controller.text = dateInput(date);
              },
      ),
    ),
  );

  Widget _notesField() => TextFormField(
    controller: _notes,
    enabled: !_busy && !_blocked,
    minLines: 2,
    maxLines: 4,
    maxLength: 1000,
    validator: (v) =>
        (v?.length ?? 0) > 1000 ? 'Maximum 1000 characters' : null,
    decoration: const InputDecoration(
      labelText: 'Notes (optional)',
      alignLabelWithHint: true,
    ),
  );

  Widget _storageField({bool compact = false}) => _select(
    'Storage space',
    _space,
    _spaces,
    (v) => setState(() => _space = v),
    compact: compact,
  );

  Widget _addSpaceButton() => Align(
    alignment: Alignment.centerRight,
    child: TextButton(
      onPressed: _busy || _blocked
          ? null
          : () async {
              setState(() => _busy = true);
              await editSpace(context, widget.workspace);
              if (!mounted) return;
              setState(() => _busy = false);
              await _load();
            },
      child: const Text('Add storage space'),
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
    ValueChanged<String?> onChange, {
    bool compact = false,
  }) => SelectionField(
    label: label,
    value: selected,
    options: {
      for (final item in items) item['id'] as String: item['name'] as String,
    },
    validator: requiredValue,
    decoration: InputDecoration(labelText: compact ? null : label),
    onChanged: _busy || _blocked ? null : onChange,
  );
}
