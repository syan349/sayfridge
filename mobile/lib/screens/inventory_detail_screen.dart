import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../state/inventory_detail_controller.dart';
import '../repositories/workspace_repository.dart';
import '../widgets/inventory_actions.dart';
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
      InventoryDetailStatus.loaded => _DetailContent(
        item: controller.item!,
        workspace: controller.workspace,
        reload: () => controller.loadItem(widget.itemId),
      ),
    };
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.item,
    required this.workspace,
    required this.reload,
  });

  final InventoryItem item;
  final WorkspaceRepository? workspace;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(25, 7, 25, 36),
      children: [
        _DetailPanel(item: item),
        const SizedBox(height: 16),
        const QuantityLegend(),
        const SizedBox(height: 45),
        InventoryActions(item: item, workspace: workspace, reload: reload),
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
