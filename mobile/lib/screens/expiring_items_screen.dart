import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../state/expiry_summary_controller.dart';
import '../state/inventory_controller.dart';
import '../state/storage_space_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
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
                    child: Row(
                      children: [
                        Flexible(
                          child: _SpacePicker(
                            controller: controller,
                            spacesController: storageSpaceController,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SearchButton(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => InventorySearchScreen(
                                  controller: inventoryController,
                                  storageSpaceController:
                                      storageSpaceController,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          onPressed: () => _showBucketFilter(context),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                          icon: Image.asset(
                            HomeAssets.filter,
                            width: 22,
                            height: 22,
                          ),
                          tooltip: 'Filter expiry group',
                        ),
                      ],
                    ),
                  ),
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
                    'Next 3 days | ${controller.counts.today + controller.counts.upcoming} items',
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Filter expiry group',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              for (final choice in const <(String, String?)>[
                ('All', null),
                ('Expired', 'overdue'),
                ('Today', 'today'),
                ('Upcoming', 'upcoming'),
              ])
                ListTile(
                  title: Text(choice.$1),
                  trailing: Icon(
                    controller.bucket == choice.$2
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    controller.selectBucket(choice.$2);
                  },
                ),
            ],
          ),
        ),
      ),
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
  const _SpacePicker({required this.controller, this.spacesController});

  final ExpirySummaryController controller;
  final StorageSpaceController? spacesController;

  @override
  Widget build(BuildContext context) {
    final spaces = <String, String>{};
    for (final entry in controller.items) {
      spaces[entry.item.storageSpaceId] = entry.item.storageSpaceName;
    }
    for (final space in spacesController?.storageSpaces ?? const []) {
      spaces[space.id] = space.name;
    }
    return ActionChip(
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFE6EDDF)),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              controller.storageSpaceId == null
                  ? 'All Spaces'
                  : spaces[controller.storageSpaceId] ?? 'Selected space',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 19),
        ],
      ),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.background,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Choose storage space',
                  style: TextStyle(fontSize: 21),
                ),
              ),
              ListTile(
                title: const Text('All Spaces'),
                onTap: () => _select(sheetContext, null),
              ),
              for (final space in spaces.entries)
                ListTile(
                  title: Text(space.value),
                  onTap: () => _select(sheetContext, space.key),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(BuildContext sheetContext, String? id) {
    Navigator.pop(sheetContext);
    controller.selectStorageSpace(id);
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE6EDDF)),
        ),
        child: Row(
          children: [
            Image.asset(HomeAssets.search, width: 21, height: 21),
            const SizedBox(width: 6),
            const Flexible(
              child: Text(
                'Search items ...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
