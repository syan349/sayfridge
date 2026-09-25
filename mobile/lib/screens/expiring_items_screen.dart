import 'package:flutter/material.dart';

import '../models/expiry_summary.dart';
import '../state/expiry_summary_controller.dart';
import '../state/inventory_controller.dart';
import '../widgets/app_background.dart';
import 'inventory_detail_screen.dart';

class ExpiringItemsScreen extends StatelessWidget {
  const ExpiringItemsScreen({
    required this.controller,
    required this.inventoryController,
    super.key,
  });

  final ExpirySummaryController controller;
  final InventoryController inventoryController;

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
                      animation: controller,
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
              'Expiring items',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return switch (controller.status) {
      ExpirySummaryLoadStatus.initial || ExpirySummaryLoadStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      ExpirySummaryLoadStatus.error => _ExpiryError(
        message: controller.errorMessage ?? 'Please try again.',
        onRetry: controller.reload,
      ),
      ExpirySummaryLoadStatus.empty ||
      ExpirySummaryLoadStatus.loaded => _buildSummary(context),
    };
  }

  Widget _buildSummary(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _ExpiryCountsRow(counts: controller.counts),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _bucketChip(label: 'All', value: null),
              _bucketChip(label: 'Overdue', value: 'overdue'),
              _bucketChip(label: 'Today', value: 'today'),
              _bucketChip(label: 'Upcoming', value: 'upcoming'),
            ],
          ),
          const SizedBox(height: 20),
          if (controller.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Column(
                children: [
                  Icon(Icons.event_available_outlined, size: 64),
                  SizedBox(height: 16),
                  Text('No items in this expiry group.'),
                ],
              ),
            )
          else
            for (final summaryItem in controller.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ExpiryItemCard(
                  summaryItem: summaryItem,
                  onTap: () => _openDetails(context, summaryItem),
                ),
              ),
          if (controller.page > 1 || controller.hasNextPage) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: controller.page > 1
                      ? () => controller.loadPage(controller.page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Previous'),
                ),
                Text('Page ${controller.page}'),
                TextButton.icon(
                  onPressed: controller.hasNextPage
                      ? () => controller.loadPage(controller.page + 1)
                      : null,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bucketChip({required String label, required String? value}) {
    return ChoiceChip(
      label: Text(label),
      selected: controller.bucket == value,
      onSelected: (_) => controller.selectBucket(value),
    );
  }

  void _openDetails(BuildContext context, ExpirySummaryItem summaryItem) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryDetailScreen(
          itemId: summaryItem.item.id,
          controller: inventoryController.createDetailController(),
        ),
      ),
    );
  }
}

class _ExpiryCountsRow extends StatelessWidget {
  const _ExpiryCountsRow({required this.counts});

  final ExpiryCounts counts;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ExpiryCount(label: 'Overdue', value: counts.overdue),
        _ExpiryCount(label: 'Today', value: counts.today),
        _ExpiryCount(label: 'Upcoming', value: counts.upcoming),
      ],
    );
  }
}

class _ExpiryCount extends StatelessWidget {
  const _ExpiryCount({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ExpiryItemCard extends StatelessWidget {
  const _ExpiryItemCard({required this.summaryItem, required this.onTap});

  final ExpirySummaryItem summaryItem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = summaryItem.item;

    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const CircleAvatar(child: Icon(Icons.event_outlined)),
        title: Text(
          item.itemDefinitionName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${item.displayQuantity} · ${item.storageSpaceName}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_bucketLabel(summaryItem.bucket)),
            const SizedBox(height: 4),
            Text(_date(item.expiryDate)),
          ],
        ),
      ),
    );
  }

  String _bucketLabel(String value) {
    return switch (value) {
      'overdue' => 'Overdue',
      'today' => 'Today',
      'upcoming' => 'Upcoming',
      _ => value,
    };
  }

  String _date(DateTime? value) {
    if (value == null) return '';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _ExpiryError extends StatelessWidget {
  const _ExpiryError({required this.message, required this.onRetry});

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
              'Unable to load expiring items',
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
