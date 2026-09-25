import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../state/inventory_detail_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/inventory_visuals.dart';

class InventoryDetailScreen extends StatefulWidget {
  const InventoryDetailScreen({
    required this.itemId,
    required this.controller,
    super.key,
  });

  final String itemId;
  final InventoryDetailController controller;

  @override
  State<InventoryDetailScreen> createState() => _InventoryDetailScreenState();
}

class _InventoryDetailScreenState extends State<InventoryDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadItem(widget.itemId);
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  const OverviewHeader(title: 'Item details'),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: widget.controller,
                      builder: (context, child) => _buildContent(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final controller = widget.controller;
    return switch (controller.status) {
      InventoryDetailStatus.initial || InventoryDetailStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      InventoryDetailStatus.error => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                controller.errorMessage ?? 'Unable to load item.',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => controller.loadItem(widget.itemId),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      InventoryDetailStatus.loaded => _DetailContent(item: controller.item!),
    };
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(25, 7, 25, 36),
      children: [
        _DetailPanel(item: item),
        const SizedBox(height: 16),
        const QuantityLegend(),
        const SizedBox(height: 45),
        SizedBox(
          height: 53,
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _EditItemScreen(item: item),
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit item', style: TextStyle(fontSize: 19)),
          ),
        ),
        const SizedBox(height: 17),
        SizedBox(
          height: 53,
          child: OutlinedButton.icon(
            onPressed: () => _showPending(context, 'Operation history'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.black),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.schedule),
            label: const Text(
              'Operation history',
              style: TextStyle(fontSize: 19),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 18, 17, 18),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFA8D589)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          InventoryArtwork(item: item, size: 135),
          const SizedBox(height: 19),
          _DetailRow(label: 'Item name', value: item.itemDefinitionName),
          _DetailRow(
            label: 'Quantity',
            value: quantityLabel(item),
            color: item.isEstimated
                ? const Color(0xFFD75A20)
                : const Color(0xFF388D38),
          ),
          _DetailRow(
            label: 'Added on',
            value: _date(item.purchaseDate ?? item.createdAt),
          ),
          _DetailRow(
            label: 'Expiry date',
            value: _date(item.expiryDate),
            color: const Color(0xFF388D38),
          ),
          _DetailRow(label: 'Storage space', value: item.storageSpaceName),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF757575),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, color: color ?? Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditItemScreen extends StatefulWidget {
  const _EditItemScreen({required this.item});

  final InventoryItem item;

  @override
  State<_EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<_EditItemScreen> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _unit;
  late final TextEditingController _purchase;
  late final TextEditingController _expiry;
  late final TextEditingController _space;
  late bool _quantityEstimated;
  late bool _expiryEstimated;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item.itemDefinitionName);
    _amount = TextEditingController(
      text: item.displayAmount.toStringAsFixed(
        item.displayAmount == item.displayAmount.truncateToDouble() ? 0 : 1,
      ),
    );
    _unit = TextEditingController(text: item.displayUnit);
    _purchase = TextEditingController(
      text: _date(item.purchaseDate ?? item.createdAt),
    );
    _expiry = TextEditingController(text: _date(item.expiryDate));
    _space = TextEditingController(text: item.storageSpaceName);
    _quantityEstimated = item.isEstimated;
    _expiryEstimated = false;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _amount,
      _unit,
      _purchase,
      _expiry,
      _space,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  const OverviewHeader(title: 'Item details'),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(25, 7, 25, 36),
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(17, 18, 17, 18),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFA8D589)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              InventoryArtwork(item: widget.item, size: 135),
                              const SizedBox(height: 15),
                              _FormRow(label: 'Item name', field: _name),
                              Row(
                                children: [
                                  Expanded(
                                    child: _FormField(
                                      label: 'Quantity',
                                      controller: _amount,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _FormField(
                                      label: 'Unit',
                                      controller: _unit,
                                    ),
                                  ),
                                ],
                              ),
                              _TypeChoice(
                                value: _quantityEstimated,
                                onChanged: (value) =>
                                    setState(() => _quantityEstimated = value),
                              ),
                              const SizedBox(height: 14),
                              _FormRow(label: 'Added on', field: _purchase),
                              _FormRow(label: 'Expiry date', field: _expiry),
                              _TypeChoice(
                                value: _expiryEstimated,
                                onChanged: (value) =>
                                    setState(() => _expiryEstimated = value),
                              ),
                              const SizedBox(height: 14),
                              _FormRow(label: 'Storage space', field: _space),
                            ],
                          ),
                        ),
                        const SizedBox(height: 45),
                        SizedBox(
                          height: 53,
                          child: FilledButton(
                            onPressed: () =>
                                _showPending(context, 'Saving item changes'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.black,
                            ),
                            child: const Text(
                              'Save changes',
                              style: TextStyle(fontSize: 19),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({required this.label, required this.field});

  final String label;
  final TextEditingController field;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF757575),
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(flex: 5, child: _Input(controller: field)),
      ],
    ),
  );
}

class _FormField extends StatelessWidget {
  const _FormField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF757575),
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 7),
      _Input(controller: controller),
    ],
  );
}

class _Input extends StatelessWidget {
  const _Input({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFFA8D589)),
      ),
    ),
  );
}

class _TypeChoice extends StatelessWidget {
  const _TypeChoice({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text(
        'Type',
        style: TextStyle(
          fontSize: 15,
          color: Color(0xFF757575),
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        flex: 3,
        child: InkWell(
          onTap: () => onChanged(true),
          child: Row(
            children: [
              Icon(
                value
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
              ),
              const SizedBox(width: 4),
              const Flexible(
                child: Text(
                  'AI-estimate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Color(0xFF757575)),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        flex: 2,
        child: InkWell(
          onTap: () => onChanged(false),
          child: Row(
            children: [
              Icon(
                !value
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
              ),
              const SizedBox(width: 4),
              const Flexible(
                child: Text(
                  'Exact',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Color(0xFF757575)),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

String _date(DateTime? value) {
  if (value == null) return 'Not set';
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
  return '${value.day.toString().padLeft(2, '0')} ${months[value.month - 1]} ${value.year}';
}

void _showPending(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '$feature is not connected to the backend yet. No changes were saved.',
      ),
    ),
  );
}
