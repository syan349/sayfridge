import 'package:flutter/material.dart';
import '../widgets/selection_sheet.dart';

import '../widgets/page_scroll_fade.dart';

import '../models/inventory_item.dart';
import '../state/expiry_summary_controller.dart';
import '../state/inventory_controller.dart';
import '../state/storage_space_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/inventory_toolbar.dart';
import '../widgets/storage_space_picker.dart';
import '../widgets/inventory_visuals.dart';
import 'inventory_detail_screen.dart';
import 'inventory_screen.dart';

class ExpiringItemsScreen extends StatelessWidget {
  const ExpiringItemsScreen({
    required this.controller,
    required this.inventoryController,
    this.storageSpaceController,
    super.key,
  });

  final ExpirySummaryController controller;
  final InventoryController inventoryController;
  final StorageSpaceController? storageSpaceController;

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
                  const OverviewHeader(title: 'Expiry Overview'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(25, 8, 25, 7),
                    child: InventoryToolbar(
                      storagePicker: _SpacePicker(
                        controller: controller,
                        spacesController: storageSpaceController,
                        inventoryController: inventoryController,
                      ),
                      onSearch: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => InventorySearchScreen(
                            controller: inventoryController,
                            storageSpaceController: storageSpaceController,
                          ),
                        ),
                      ),
                      onFilter: () => _showBucketFilter(context),
                      filterTooltip: 'Filter expiry group',
                    ),
                  ),
                  Expanded(
                    child: PageScrollFade(
                      child: AnimatedBuilder(
                        animation: controller,
                        builder: (context, child) => _buildContent(context),
                      ),
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

  Widget _buildContent(BuildContext context) {
    return switch (controller.status) {
      ExpirySummaryLoadStatus.initial || ExpirySummaryLoadStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      ExpirySummaryLoadStatus.error => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                controller.errorMessage ?? 'Unable to load expiring items.',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: controller.reload,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      ExpirySummaryLoadStatus.empty ||
      ExpirySummaryLoadStatus.loaded => _buildSummary(context),
    };
  }

  Widget _buildSummary(BuildContext context) {
    final overdue = controller.items
        .where((entry) => entry.bucket == 'overdue')
        .toList();
    final soon = controller.items
        .where((entry) => entry.bucket != 'overdue')
        .toList();
    return RefreshIndicator(
      onRefresh: controller.reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(25, 8, 25, 32),
        children: [
          if (controller.bucket == null || controller.bucket == 'overdue') ...[
            const Text(
              'Expired',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            if (overdue.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'No expired items',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            for (final entry in overdue)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InventoryItemTile(
                  item: entry.item,
                  onTap: () => _openDetails(context, entry.item),
                ),
              ),
            const SizedBox(height: 23),
          ],
          if (controller.bucket != 'overdue') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Expiry soon',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Next ${controller.daysBefore} days | ${controller.counts.today + controller.counts.upcoming} items',
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            const QuantityLegend(),
            const SizedBox(height: 15),
            if (soon.isEmpty)
              Column(
                children: [
                  Image.asset(HomeAssets.noExpiry, width: 105, height: 105),
                  const Text(
                    'No items expiring soon',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            for (final entry in soon)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InventoryItemTile(
                  item: entry.item,
                  onTap: () => _openDetails(context, entry.item),
                ),
              ),
          ],
          if (controller.page > 1 || controller.hasNextPage)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: controller.page > 1
                      ? () => controller.loadPage(controller.page - 1)
                      : null,
                  child: const Text('Previous'),
                ),
                Text('Page ${controller.page}'),
                TextButton(
                  onPressed: controller.hasNextPage
                      ? () => controller.loadPage(controller.page + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showBucketFilter(BuildContext context) {
    showSelectionSheet<String?>(
      context,
      title: 'Filter expiry group',
      selected: controller.bucket,
      options: const [
        ('All', null),
        ('Expired', 'overdue'),
        ('Today', 'today'),
        ('Upcoming', 'upcoming'),
      ],
      onSelected: controller.selectBucket,
    );
  }

  void _openDetails(BuildContext context, InventoryItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryDetailScreen(
          itemId: item.id,
          controller: inventoryController.createDetailController(),
        ),
      ),
    );
  }
}

class _SpacePicker extends StatelessWidget {
  const _SpacePicker({
    required this.controller,
    required this.inventoryController,
    this.spacesController,
  });
  final ExpirySummaryController controller;
  final InventoryController inventoryController;
  final StorageSpaceController? spacesController;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, spacesController]),
    builder: (context, _) {
      final spaces = <String, String>{};
      for (final entry in controller.items) {
        spaces[entry.item.storageSpaceId] = entry.item.storageSpaceName;
      }
      for (final space in spacesController?.storageSpaces ?? const []) {
        spaces[space.id] = space.name;
      }
      return StoragePickerButton(
        label: controller.storageSpaceId == null
            ? 'All Spaces'
            : spaces[controller.storageSpaceId] ?? 'Selected space',
        onTap: () => showStorageSpacePicker(
          context,
          selectedId: controller.storageSpaceId,
          fallbackSpaces: spaces,
          spacesController: spacesController,
          inventoryController: inventoryController,
          onSelected: controller.selectStorageSpace,
        ),
      );
    },
  );
}
