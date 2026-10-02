import 'package:flutter/material.dart';

import '../widgets/page_scroll_fade.dart';

import '../models/inventory_item.dart';
import '../models/item_definition.dart';
import '../repositories/item_artwork_repository.dart';
import '../repositories/workspace_repository.dart';
import '../widgets/storage_space_management.dart';
import '../state/manual_stock_in_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/selection_field.dart';
import '../widgets/inventory_visuals.dart';
import '../widgets/item_icon_picker.dart';

class ManualStockInScreen extends StatefulWidget {
  const ManualStockInScreen({
    required this.controller,
    this.artworkRepository = const ItemArtworkRepository(),
    this.workspace,
    super.key,
  });

  final ManualStockInController controller;
  final ItemArtworkRepository artworkRepository;
  final WorkspaceRepository? workspace;

  @override
  State<ManualStockInScreen> createState() => _ManualStockInScreenState();
}

class _ManualStockInScreenState extends State<ManualStockInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  String? _selectedArtwork;
  bool _savingArtwork = false;
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
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final busy =
        widget.controller.status == ManualStockInStatus.submitting ||
        _savingArtwork;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    const OverviewHeader(title: 'Add item'),
                    Expanded(
                      child: switch (widget.controller.status) {
                        ManualStockInStatus.initial ||
                        ManualStockInStatus.loading => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        ManualStockInStatus.error => _LoadError(
                          message: widget.controller.errorMessage,
                          onRetry: widget.controller.loadOptions,
                        ),
                        _ => _buildForm(context),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final controller = widget.controller;
    final isSubmitting =
        controller.status == ManualStockInStatus.submitting || _savingArtwork;
    final enabled = !isSubmitting && !controller.submissionUncertain;
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
          fillColor: const Color(0x80FFFFFF),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFFA8D589)),
          ),
        ),
      ),
      child: Form(
        key: _formKey,
        child: PageScrollFade(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(25, 7, 25, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFA8D589)),
                  borderRadius: BorderRadius.circular(16),
                  color: const Color(0x35FFFFFF),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ItemIconPicker(
                      name: _nameController.text,
                      selectedAsset: _selectedArtwork,
                      enabled: enabled,
                      onChanged: (asset) =>
                          setState(() => _selectedArtwork = asset),
                    ),
                    const SizedBox(height: 20),
                    _labelRow('Item name', _nameField(enabled)),
                    const SizedBox(height: 20),
                    _labelRow(
                      'Category',
                      SelectionField(
                        label: 'Category',
                        decoration: const InputDecoration(),
                        value: controller.selectedCategoryId,
                        options: {
                          for (final category in controller.categories)
                            category.id: category.name,
                        },
                        onChanged: enabled ? controller.selectCategory : null,
                        sortAlphabetically: true,
                        onCreateOption: controller.createCategory,
                        validator: (value) =>
                            value == null ? 'Choose a category.' : null,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                                key: const Key('add-item-quantity'),
                                controller: _amountController,
                                enabled: enabled,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: const TextStyle(
                                  color: Color(0xFF388D38),
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Quantity',
                                ),
                                validator: _validateAmount,
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
                                key: const Key('add-item-unit'),
                                controller: _unitController,
                                enabled: enabled,
                                decoration: const InputDecoration(
                                  hintText: 'Unit',
                                ),
                                validator: _validateUnit,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _labelRow(
                      'Purchase date',
                      _DateField(
                        label: 'Purchase date',
                        value: _purchaseDate,
                        enabled: enabled,
                        onChanged: (value) =>
                            setState(() => _purchaseDate = value),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _labelRow(
                      'Expiry date',
                      _DateField(
                        label: 'Expiry date',
                        value: _expiryDate,
                        enabled: enabled,
                        onChanged: (value) =>
                            setState(() => _expiryDate = value),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _labelRow(
                      'Storage space',
                      SelectionField(
                        label: 'Storage space',
                        decoration: const InputDecoration(),
                        value: controller.selectedStorageSpaceId,
                        options: {
                          for (final space in controller.storageSpaces)
                            space.id: space.name,
                        },
                        onChanged: enabled
                            ? controller.selectStorageSpace
                            : null,
                        onManage: widget.workspace == null
                            ? null
                            : () async {
                                await manageStorageSpaces(
                                  context,
                                  widget.workspace!,
                                );
                                if (!mounted) return;
                                try {
                                  await controller.reloadStorageSpaces();
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(businessError(error)),
                                      ),
                                    );
                                  }
                                }
                              },
                        validator: (value) =>
                            value == null ? 'Choose a storage space.' : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesController,
                      enabled: enabled,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller.errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed:
                    !enabled ||
                        controller.isLoadingDefinitions ||
                        !controller.hasRequiredOptions
                    ? null
                    : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.text,
                  minimumSize: const Size.fromHeight(54),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
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
      ),
    );
  }

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

  Widget _nameField(bool enabled) => LayoutBuilder(
    builder: (context, constraints) => RawAutocomplete<ItemDefinition>(
      textEditingController: _nameController,
      focusNode: _nameFocus,
      displayStringForOption: (item) => item.name,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty ||
            !enabled ||
            widget.controller.isLoadingDefinitions) {
          return const Iterable<ItemDefinition>.empty();
        }
        return widget.controller.definitions.where(
          (item) => item.name.toLowerCase().contains(query),
        );
      },
      onSelected: (item) {
        widget.controller.selectDefinition(item.id);
        setState(() {});
      },
      fieldViewBuilder: (context, controller, focus, onSubmitted) =>
          TextFormField(
            key: const Key('add-item-name'),
            controller: controller,
            focusNode: focus,
            enabled: enabled,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: (_) => onSubmitted(),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? 'Enter an item name.'
                : value!.trim().length > 100
                ? 'Maximum 100 characters'
                : null,
            decoration: InputDecoration(
              hintText: 'Item name',
              suffixIconConstraints: const BoxConstraints(
                minWidth: 34,
                minHeight: 40,
              ),
              suffixIcon: widget.controller.isLoadingDefinitions
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Choose existing item',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 22),
                      onPressed: enabled ? _chooseExistingItem : null,
                    ),
            ),
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 3,
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: constraints.maxWidth,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final item = options.elementAt(index);
                  return ListTile(
                    title: Text(item.name),
                    onTap: () => onSelected(item),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _chooseExistingItem() async {
    _nameFocus.unfocus();
    final id = await showSelectionSheet(
      context,
      title: 'Choose item',
      options: {
        for (final item in widget.controller.definitions) item.id: item.name,
      },
      selected: widget.controller.selectedDefinitionId,
    );
    if (!mounted || id == null) return;
    final item = widget.controller.definitions
        .where((item) => item.id == id)
        .firstOrNull;
    if (item == null) return;
    _nameController.text = item.name;
    widget.controller.selectDefinition(id);
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _nameFocus.unfocus();

    final success = await widget.controller.submit(
      amount: _amountController.text,
      unit: _unitController.text,
      purchaseDate: _purchaseDate,
      expiryDate: _expiryDate,
      notes: _notesController.text,
      itemName: _nameController.text,
    );

    if (!success || !mounted) return;
    final item = widget.controller.createdItem;
    var message = 'Inventory item added.';
    if (_selectedArtwork != null && item != null) {
      setState(() => _savingArtwork = true);
      try {
        await widget.artworkRepository.save(item.id, _selectedArtwork!);
      } catch (_) {
        message = 'Item added, but the icon could not be saved on this device.';
      }
      if (!mounted) return;
      setState(() => _savingArtwork = false);
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
          hintText: 'Not set',
          suffixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 40,
          ),
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_outlined, size: 19)
              : IconButton(
                  tooltip: 'Clear $label',
                  onPressed: enabled ? () => onChanged(null) : null,
                  icon: const Icon(Icons.clear, size: 19),
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
