import 'package:flutter/material.dart';

import 'page_scroll_fade.dart';

import '../models/inventory_item.dart';
import '../repositories/workspace_repository.dart';
import '../screens/stock_editor_screen.dart';
import 'business_forms.dart';
import 'app_background.dart';
import 'inventory_visuals.dart';
import 'app_action_icon.dart';
import '../theme/app_theme.dart';

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

  bool get _isExpired {
    final expiryDate = item.expiryDate;
    if (expiryDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return expiry.isBefore(today);
  }

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

  Future<void> _markUsedUp(BuildContext context) async {
    final key = requestId();
    final confirmed = await businessForm(
      context,
      title: 'Mark this item as used up?',
      fields: const [],
      idempotentRetry: true,
      explanation:
          '${item.itemDefinitionName}\nThe remaining quantity will be set to 0 and the item will move out of the active inventory. Its history will be kept.',
      submit: (_) async {
        await workspace!.quantityOperation(item.id, {
          'expected_version': item.version,
          'operation_type': 'RECONCILE',
          'quantity_kind': 'AMOUNT',
          'quantity_value': '0',
          'quantity_unit': item.displayUnit,
        }, key);
      },
    );
    if (confirmed == true && context.mounted) await reload();
  }

  Future<void> _quantityActions(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Manage quantity',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                ),
              ),
              for (final action in <(String, String, IconData)>[
                ('ADD', 'Add quantity', Icons.add_circle_outline),
                if (item.isInStock)
                  ('CONSUME', 'Use quantity', Icons.remove_circle_outline),
                if (item.isInStock)
                  ('fraction', 'Use a fraction', Icons.pie_chart_outline),
                ('RECONCILE', 'Confirm remaining', Icons.fact_check_outlined),
              ])
                ListTile(
                  leading: Icon(action.$3, color: AppColors.userMessage),
                  title: Text(action.$2),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(sheetContext, action.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    await _quantity(
      context,
      choice == 'fraction' ? 'CONSUME' : choice,
      fraction: choice == 'fraction',
    );
  }

  @override
  Widget build(BuildContext context) {
    final editable = item.status == 'IN_STOCK' || item.status == 'EMPTY';
    final secondaryStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      foregroundColor: AppColors.userMessage,
      side: const BorderSide(color: Color(0xFFA8D589)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (workspace == null) ...[
          const Text(
            'Offline preview: inventory writes are disabled.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
        ],
        if (editable) ...[
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
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
            child: const _ActionLabel(
              icon: AppActionIcon(ActionAssets.edit, size: 16),
              label: 'Edit item',
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton(
          style: secondaryStyle,
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
          child: const _ActionLabel(
            icon: Icon(Icons.schedule, size: 20),
            label: 'Operation history',
          ),
        ),
        if (editable) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            style: secondaryStyle,
            onPressed: workspace == null
                ? null
                : () => _quantityActions(context),
            child: const _ActionLabel(
              icon: Icon(Icons.tune, size: 20),
              label: 'Quantity',
            ),
          ),
          if (item.isInStock) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              style: secondaryStyle,
              onPressed: workspace == null ? null : () => _markUsedUp(context),
              child: const _ActionLabel(
                icon: Icon(Icons.check_circle_outline, size: 20),
                label: 'Mark as used up',
              ),
            ),
          ],
          if (item.isInStock && _isExpired) ...[
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: workspace == null
                  ? null
                  : () => _state(context, 'discard'),
              child: const _ActionLabel(
                icon: AppActionIcon(ActionAssets.deleteWhite, size: 20),
                label: 'Discard expired item',
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _ActionLabel extends StatelessWidget {
  const _ActionLabel({required this.icon, required this.label});
  final Widget icon;
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 184),
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            SizedBox(width: 24, height: 24, child: Center(child: icon)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Arial'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
              child: PageScrollFade(
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
            ),
          ],
        ),
      ),
    ),
  );
}
