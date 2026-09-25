import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../state/inventory_detail_controller.dart';
import '../widgets/app_background.dart';

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
                  _buildHeader(context),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: widget.controller,
                      builder: (context, child) => _buildContent(context),
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

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Item details',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final controller = widget.controller;

    return switch (controller.status) {
      InventoryDetailStatus.initial || InventoryDetailStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      InventoryDetailStatus.error => _DetailError(
        message: controller.errorMessage ?? 'Please try again.',
        onRetry: () => controller.loadItem(widget.itemId),
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
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      children: [
        const Icon(Icons.inventory_2_outlined, size: 72),
        const SizedBox(height: 16),
        Text(
          item.itemDefinitionName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 28),
        _DetailCard(
          children: [
            _DetailRow(label: 'Quantity', value: item.displayQuantity),
            _DetailRow(label: 'Status', value: _displayStatus(item.status)),
            _DetailRow(label: 'Storage space', value: item.storageSpaceName),
            _DetailRow(label: 'Category', value: item.categoryName),
            _DetailRow(
              label: 'Purchase date',
              value: _displayDate(item.purchaseDate),
            ),
            _DetailRow(
              label: 'Expiry date',
              value: _displayDate(item.expiryDate),
            ),
            _DetailRow(
              label: 'Quantity source',
              value: item.isEstimated ? 'Estimated' : 'Confirmed',
            ),
            _DetailRow(label: 'Notes', value: item.notes ?? 'None'),
          ],
        ),
      ],
    );
  }

  String _displayDate(DateTime? value) {
    if (value == null) return 'Not set';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _displayStatus(String value) {
    return value
        .toLowerCase()
        .split('_')
        .map((word) {
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(children: children),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              'Unable to load item',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
