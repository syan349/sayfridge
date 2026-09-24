import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../state/inventory_controller.dart';
import '../widgets/app_background.dart';
import 'inventory_detail_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({required this.controller, super.key});

  final InventoryController controller;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.controller.query);
  }

  @override
  void dispose() {
    _searchController.dispose();
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: SearchBar(
                      controller: _searchController,
                      hintText: 'Search inventory...',
                      leading: const Icon(Icons.search),
                      trailing: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear search',
                          ),
                      ],
                      onChanged: (_) => setState(() {}),
                      onSubmitted: _search,
                    ),
                  ),
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
              'Inventory',
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
      InventoryLoadStatus.initial || InventoryLoadStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      InventoryLoadStatus.empty => _InventoryMessage(
        icon: Icons.inventory_2_outlined,
        title: controller.query.isEmpty
            ? 'Your inventory is empty'
            : 'No matching items',
        message: controller.query.isEmpty
            ? 'Inventory items will appear here.'
            : 'Try a different search term.',
        actionLabel: 'Refresh',
        onAction: controller.reload,
      ),
      InventoryLoadStatus.error => _InventoryMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Unable to load inventory',
        message: controller.errorMessage ?? 'Please try again.',
        actionLabel: 'Try again',
        onAction: controller.reload,
      ),
      InventoryLoadStatus.loaded => _buildLoadedContent(context),
    };
  }

  Widget _buildLoadedContent(BuildContext context) {
    final controller = widget.controller;

    return RefreshIndicator(
      onRefresh: controller.reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            '${controller.total} ${controller.total == 1 ? 'item' : 'items'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          for (final item in controller.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _InventoryItemCard(
                item: item,
                onTap: () => _openDetails(item),
              ),
            ),
          if (controller.page > 1 || controller.hasNextPage) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: controller.page > 1
                      ? () => _loadPage(controller.page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Previous'),
                ),
                Text('Page ${controller.page}'),
                TextButton.icon(
                  onPressed: controller.hasNextPage
                      ? () => _loadPage(controller.page + 1)
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

  void _search(String value) {
    widget.controller.loadInventory(
      query: value.trim(),
      storageSpaceId: widget.controller.storageSpaceId,
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
    widget.controller.loadInventory(
      storageSpaceId: widget.controller.storageSpaceId,
    );
  }

  void _loadPage(int page) {
    widget.controller.loadInventory(
      status: widget.controller.inventoryStatus,
      query: widget.controller.query,
      storageSpaceId: widget.controller.storageSpaceId,
      page: page,
      pageSize: widget.controller.pageSize,
    );
  }

  void _openDetails(InventoryItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryDetailScreen(
          itemId: item.id,
          controller: widget.controller.createDetailController(),
        ),
      ),
    );
  }
}

class _InventoryItemCard extends StatelessWidget {
  const _InventoryItemCard({required this.item, required this.onTap});

  final InventoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
        title: Text(
          item.itemDefinitionName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${item.displayQuantity} · ${item.storageSpaceName}\n${item.categoryName}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _InventoryMessage extends StatelessWidget {
  const _InventoryMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
