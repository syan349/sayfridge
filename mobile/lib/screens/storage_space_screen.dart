import 'package:flutter/material.dart';

import '../models/storage_space.dart';
import '../state/storage_space_controller.dart';
import '../widgets/app_background.dart';

class StorageSpaceScreen extends StatelessWidget {
  const StorageSpaceScreen({
    required this.controller,
    this.onSelected,
    super.key,
  });

  final StorageSpaceController controller;
  final ValueChanged<StorageSpace?>? onSelected;

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
                  Padding(
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
                            'Storage Spaces',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
      StorageSpaceLoadStatus.initial || StorageSpaceLoadStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      StorageSpaceLoadStatus.empty => _StorageSpaceMessage(
        icon: Icons.kitchen_outlined,
        title: 'No storage spaces yet',
        message: 'Your active storage spaces will appear here.',
        actionLabel: 'Refresh',
        onAction: controller.loadStorageSpaces,
      ),
      StorageSpaceLoadStatus.error => _StorageSpaceMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Unable to load storage spaces',
        message: controller.errorMessage ?? 'Please try again.',
        actionLabel: 'Try again',
        onAction: controller.loadStorageSpaces,
      ),
      StorageSpaceLoadStatus.loaded => _buildLoadedContent(context),
    };
  }

  Widget _buildLoadedContent(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.loadStorageSpaces,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            '${controller.total} active ${controller.total == 1 ? 'space' : 'spaces'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          if (onSelected != null) ...[
            Card(
              child: ListTile(
                onTap: () => onSelected!(null),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                leading: const CircleAvatar(child: Icon(Icons.apps)),
                title: const Text(
                  'All Spaces',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final space in controller.storageSpaces)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _StorageSpaceCard(
                space: space,
                onTap: onSelected == null ? null : () => onSelected!(space),
              ),
            ),
          if (controller.page > 1 || controller.hasNextPage) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: controller.page > 1
                      ? () => controller.loadStorageSpaces(
                          page: controller.page - 1,
                          pageSize: controller.pageSize,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Previous'),
                ),
                Text('Page ${controller.page}'),
                TextButton.icon(
                  onPressed: controller.hasNextPage
                      ? () => controller.loadStorageSpaces(
                          page: controller.page + 1,
                          pageSize: controller.pageSize,
                        )
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
}

class _StorageSpaceCard extends StatelessWidget {
  const _StorageSpaceCard({required this.space, this.onTap});

  final StorageSpace space;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(child: Icon(_iconForType(space.type))),
        title: Text(
          space.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(space.type),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type.toUpperCase()) {
      'FRIDGE' || 'REFRIGERATOR' => Icons.kitchen_outlined,
      'FREEZER' => Icons.ac_unit,
      'PANTRY' => Icons.inventory_2_outlined,
      _ => Icons.shelves,
    };
  }
}

class _StorageSpaceMessage extends StatelessWidget {
  const _StorageSpaceMessage({
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
