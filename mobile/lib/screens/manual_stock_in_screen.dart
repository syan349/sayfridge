import 'package:flutter/material.dart';

import '../widgets/page_scroll_fade.dart';

import '../models/inventory_item.dart';
import '../state/manual_stock_in_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/selection_field.dart';
import '../widgets/page_back_button.dart';

class ManualStockInScreen extends StatefulWidget {
  const ManualStockInScreen({required this.controller, super.key});

  final ManualStockInController controller;

  @override
  State<ManualStockInScreen> createState() => _ManualStockInScreenState();
}

class _ManualStockInScreenState extends State<ManualStockInScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _unitController;
  late final TextEditingController _notesController;
  DateTime? _purchaseDate;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _unitController = TextEditingController();
    _notesController = TextEditingController();
    widget.controller.addListener(_onControllerChanged);
    // Space/default settings may have changed since the previous visit.
    widget.controller.loadOptions();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _amountController.dispose();
    _unitController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: switch (widget.controller.status) {
            ManualStockInStatus.initial || ManualStockInStatus.loading =>
              const Center(child: CircularProgressIndicator()),
            ManualStockInStatus.error => _LoadError(
              message: widget.controller.errorMessage,
              onRetry: widget.controller.loadOptions,
            ),
            _ => _buildForm(context),
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final controller = widget.controller;
    final isSubmitting = controller.status == ManualStockInStatus.submitting;

    return Form(
      key: _formKey,
      child: PageScrollFade(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(25, 12, 25, 32),
          children: [
            Row(
              children: [
                PageBackButton(enabled: !isSubmitting),
                const SizedBox(width: 8),
                Text(
                  'Add inventory',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
            const SizedBox(height: 24),
            SelectionField(
              label: 'Storage space',
              value: controller.selectedStorageSpaceId,
              options: {
                for (final space in controller.storageSpaces)
                  space.id: space.name,
              },
              onChanged: isSubmitting ? null : controller.selectStorageSpace,
              validator: (value) =>
                  value == null ? 'Choose a storage space.' : null,
            ),
            const SizedBox(height: 16),
            SelectionField(
              label: 'Category',
              value: controller.selectedCategoryId,
              options: {
                for (final category in controller.categories)
                  category.id: category.name,
              },
              onChanged: isSubmitting ? null : controller.selectCategory,
              validator: (value) => value == null ? 'Choose a category.' : null,
            ),
            const SizedBox(height: 16),
            SelectionField(
              label: 'Item',
              key: ValueKey(controller.selectedCategoryId),
              value: controller.selectedDefinitionId,
              decoration: InputDecoration(
                labelText: 'Item',
                suffixIcon: controller.isLoadingDefinitions
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              options: {
                for (final definition in controller.definitions)
                  definition.id: definition.name,
              },
              onChanged: isSubmitting || controller.isLoadingDefinitions
                  ? null
                  : controller.selectDefinition,
              validator: (value) => value == null ? 'Choose an item.' : null,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amountController,
                    enabled: !isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    validator: _validateAmount,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _unitController,
                    enabled: !isSubmitting,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    validator: _validateUnit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DateField(
              label: 'Purchase date (optional)',
              value: _purchaseDate,
              enabled: !isSubmitting,
              onChanged: (value) => setState(() => _purchaseDate = value),
            ),
            const SizedBox(height: 16),
            _DateField(
              label: 'Expiry date (optional)',
              value: _expiryDate,
              enabled: !isSubmitting,
              onChanged: (value) => setState(() => _expiryDate = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              enabled: !isSubmitting,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (controller.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: isSubmitting || !controller.hasRequiredOptions
                  ? null
                  : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: isSubmitting
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Add to inventory'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await widget.controller.submit(
      amount: _amountController.text,
      unit: _unitController.text,
      purchaseDate: _purchaseDate,
      expiryDate: _expiryDate,
      notes: _notesController.text,
    );

    if (!success || !mounted) return;
    final item = widget.controller.createdItem;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Inventory item added.')));
    Navigator.of(context).pop<InventoryItem>(item);
  }

  String? _validateAmount(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter a quantity.';
    if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,3})?$').hasMatch(input)) {
      return 'Use a positive number with up to 3 decimals.';
    }
    final amount = double.tryParse(input);
    if (amount == null || amount <= 0 || amount > 999999999.999) {
      return 'Enter a quantity greater than 0.';
    }
    return null;
  }

  String? _validateUnit(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter a unit.';
    if (input.length > 16) return 'Use at most 16 characters.';
    return null;
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final bool enabled;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pickDate(context) : null,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_outlined)
              : IconButton(
                  onPressed: enabled ? () => onChanged(null) : null,
                  icon: const Icon(Icons.clear),
                ),
        ),
        child: Text(value == null ? 'Not set' : _formatDate(value!)),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 20),
    );
    if (selected != null) onChanged(selected);
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 72),
            const SizedBox(height: 16),
            Text(
              message ?? 'Unable to load stock-in options.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
