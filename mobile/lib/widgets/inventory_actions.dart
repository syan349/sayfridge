import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../repositories/workspace_repository.dart';
import '../screens/stock_editor_screen.dart';
import 'business_forms.dart';
import 'app_background.dart';
import 'inventory_visuals.dart';

class InventoryActions extends StatelessWidget {
  const InventoryActions({
    required this.item,
    required this.workspace,
    required this.reload,
    super.key,
  });
  final InventoryItem item;
  final WorkspaceRepository? workspace;
  final Future<void> Function() reload;

  Future<void> _quantity(
    BuildContext context,
    String operation, {
    bool fraction = false,
  }) async {
    final key =
        requestId(); // Keep this key AND literal inputs for retries of this dialog.
    await businessForm(
      context,
      title: switch (operation) {
        'ADD' => 'Add to this stock',
        'CONSUME' => 'Use stock',
        _ => 'Confirm remaining',
      },
      idempotentRetry: true,
      explanation:
          '${item.isEstimated ? 'Estimated' : 'Confirmed'} balance: ${item.displayQuantity}.\n${operation == 'RECONCILE' ? 'Enter the actual total remaining, not a change. This replaces the confirmed balance and clears the estimate.' : 'Enter the amount to ${operation == 'ADD' ? 'add' : 'use'}, not the remaining total. The server calculates the result.'}',
      fields: [
        BusinessField(
          'quantity_value',
          fraction ? 'Fraction of remaining (e.g. 1/2)' : 'Amount',
          validator: (value) {
            if (!fraction) {
              return validateAmount(value, allowZero: operation == 'RECONCILE');
            }
            if (value == null ||
                value.length > 32 ||
                !RegExp(r'^[1-9]\d*/[1-9]\d*$').hasMatch(value)) {
              return 'Enter a fraction such as 1/2';
            }
            final parts = value.split('/').map(BigInt.parse).toList();
            return parts[0] > parts[1]
                ? 'Cannot use more than the whole balance'
                : null;
          },
        ),
        BusinessField(
          'quantity_unit',
          'Unit',
          initial: fraction ? 'remaining' : item.displayUnit,
          readOnly: fraction,
          validator: requiredValue,
        ),
      ],
      submit: (values) async {
        await workspace!.quantityOperation(item.id, {
          'expected_version': item.version,
          'operation_type': operation,
          'quantity_kind': fraction ? 'FRACTION' : 'AMOUNT',
          ...values,
        }, key);
      },
    );
    if (context.mounted) await reload();
  }

  Future<void> _state(BuildContext context, String action) async {
    await businessForm(
      context,
      title: '${action == 'discard' ? 'Discard' : 'Archive'} this item?',
      fields: const [],
      explanation:
          '${item.itemDefinitionName}\nThis changes its inventory status; it does not delete its records.',
      submit: (_) async {
        await workspace!.changeState(item, action);
      },
    );
    if (context.mounted) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final editable = item.status == 'IN_STOCK' || item.status == 'EMPTY';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (workspace == null)
          const Text('Offline preview: inventory writes are disabled.'),
        if (editable)
          FilledButton.icon(
            onPressed: workspace == null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<bool>(
                        builder: (_) => StockEditorScreen(
                          workspace: workspace!,
                          item: item,
                        ),
                      ),
                    );
                    if (context.mounted) await reload();
                  },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit item'),
          ),
        if (editable && workspace != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _quantity(context, 'ADD'),
                child: const Text('Add quantity'),
              ),
              if (item.isInStock)
                OutlinedButton(
                  onPressed: () => _quantity(context, 'CONSUME'),
                  child: const Text('Use quantity'),
                ),
              if (item.isInStock)
                OutlinedButton(
                  onPressed: () =>
                      _quantity(context, 'CONSUME', fraction: true),
                  child: const Text('Use a fraction'),
                ),
              OutlinedButton(
                onPressed: () => _quantity(context, 'RECONCILE'),
                child: const Text('Confirm remaining'),
              ),
              if (item.isInStock)
                TextButton(
                  onPressed: () => _state(context, 'discard'),
                  child: const Text('Discard'),
                ),
              TextButton(
                onPressed: () => _state(context, 'archive'),
                child: const Text('Archive'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 17),
        OutlinedButton.icon(
          onPressed: workspace == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => InventoryHistoryScreen(
                      item: item,
                      workspace: workspace!,
                    ),
                  ),
                ),
          icon: const Icon(Icons.schedule),
          label: const Text('Operation history'),
        ),
      ],
    );
  }
}

class InventoryHistoryScreen extends StatefulWidget {
  const InventoryHistoryScreen({
    required this.item,
    required this.workspace,
    super.key,
  });
  final InventoryItem item;
  final WorkspaceRepository workspace;
  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _history = widget.workspace.history(
    widget.item.id,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppBackground(
      child: SafeArea(
        child: Column(
          children: [
            const OverviewHeader(title: 'Operation history'),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _history,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(businessError(snapshot.error!)),
                          TextButton(
                            onPressed: () => setState(
                              () => _history = widget.workspace.history(
                                widget.item.id,
                              ),
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final history = snapshot.data!;
                  if (history.isEmpty) {
                    return const Center(
                      child: Text(
                        'No quantity operations yet.\nInitial stock entry is not an ADD operation.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text(
                        'Quantity operations only. Metadata edits, moves and archival are not recorded here.',
                      ),
                      for (final operation in history)
                        Card(
                          child: ListTile(
                            title: Text(
                              '${operation['operation_type']} · ${operation['status']}',
                            ),
                            subtitle: Text(
                              '${operation['quantity_value']} ${operation['quantity_unit']}\n'
                              '${operation['input_method']} · ${operation['calculation_method']}\n'
                              '${operation['created_at']}\n'
                              '${operation['status'] != 'SUCCESS'
                                  ? 'Not an effective successful change'
                                  : operation['operation_type'] == 'RECONCILE'
                                  ? 'Confirmed remaining total'
                                  : 'Applied change: ${operation['applied_change_amount']} ${operation['applied_change_unit']}'}',
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
