import 'package:flutter/material.dart';
import '../widgets/app_action_icon.dart';

import '../widgets/page_scroll_fade.dart';

import '../models/storage_space.dart';
import '../state/inventory_controller.dart';
import '../state/storage_space_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/inventory_visuals.dart';
import '../widgets/business_forms.dart';
import '../repositories/workspace_repository.dart';

class StorageSpaceScreen extends StatelessWidget {
  const StorageSpaceScreen({
    required this.controller,
    this.inventoryController,
    this.onSelected,
    super.key,
  });

  final StorageSpaceController controller;
  final InventoryController? inventoryController;
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
                  const OverviewHeader(title: 'Storage spaces'),
                  const Text(
                    'Manage where you store items.',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
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
      StorageSpaceLoadStatus.initial || StorageSpaceLoadStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      StorageSpaceLoadStatus.empty => _buildLoadedContent(context),
      StorageSpaceLoadStatus.error => _Message(
        title: 'Unable to load storage spaces',
        message: controller.errorMessage ?? 'Please try again.',
        onRetry: controller.loadStorageSpaces,
      ),
      StorageSpaceLoadStatus.loaded => _buildLoadedContent(context),
    };
  }

  Widget _buildLoadedContent(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.loadStorageSpaces,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(25, 0, 25, 32),
        children: [
          if (onSelected != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _SpaceCard(
                label: 'All Spaces',
                count: inventoryController?.total,
                icon: Icons.apps,
                onTap: () => onSelected!(null),
              ),
            ),
          for (final space in controller.storageSpaces)
            Padding(
              padding: const EdgeInsets.only(bottom: 17),
              child: _SpaceCard(
                label: space.name,
                count: _countFor(space),
                icon: _iconFor(space.type),
                onTap: onSelected == null ? null : () => onSelected!(space),
                onEdit: () => _edit(context, space),
                onDelete: () => _archive(context, space),
                isDefault: space.isDefault,
                onDefault: space.isDefault || controller.workspace == null
                    ? null
                    : () => _setDefault(context, space),
              ),
            ),
          const SizedBox(height: 32),
          if (controller.workspace != null)
            OutlinedButton(
              onPressed: () => _restore(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 53),
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.black,
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 19),
              ),
              child: const Text(
                'Restore an archived space',
                style: TextStyle(fontFamily: 'Arial'),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 53,
            child: FilledButton.icon(
              onPressed: () => _edit(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.add, size: 27),
              label: const Text(
                'Add storage space',
                style: TextStyle(fontSize: 19),
              ),
            ),
          ),
          if (controller.page > 1 || controller.hasNextPage) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: controller.page > 1
                      ? () => controller.loadStorageSpaces(
                          page: controller.page - 1,
                          pageSize: controller.pageSize,
                        )
                      : null,
                  child: const Text('Previous'),
                ),
                Text('Page ${controller.page}'),
                TextButton(
                  onPressed: controller.hasNextPage
                      ? () => controller.loadStorageSpaces(
                          page: controller.page + 1,
                          pageSize: controller.pageSize,
                        )
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  int? _countFor(StorageSpace space) {
    final inventory = inventoryController;
    if (inventory == null ||
        inventory.status != InventoryLoadStatus.loaded ||
        inventory.hasNextPage ||
        inventory.storageSpaceId != null) {
      return null;
    }
    return inventory.items
        .where((item) => item.storageSpaceId == space.id)
        .length;
  }

  IconData _iconFor(String type) {
    return switch (type.toUpperCase()) {
      'FRIDGE' || 'REFRIGERATOR' => Icons.kitchen_outlined,
      'FREEZER' => Icons.ac_unit,
      'PANTRY' => Icons.warehouse_outlined,
      _ => Icons.shelves,
    };
  }

  void _notConnected(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Storage editing will be available after backend integration.',
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, [StorageSpace? space]) async {
    final workspace = controller.workspace;
    if (workspace == null) {
      _notConnected(context);
      return;
    }
    await editSpace(
      context,
      workspace,
      id: space?.id,
      name: space?.name ?? '',
      type: space?.type ?? 'FRIDGE',
    );
    if (!context.mounted) return;
    await controller.loadStorageSpaces();
  }

  Future<void> _archive(BuildContext context, StorageSpace space) async {
    final workspace = controller.workspace;
    if (workspace == null) {
      _notConnected(context);
      return;
    }
    try {
      final hasStock = await workspace.spaceHasStock(space.id);
      if (!context.mounted) return;
      if (hasStock) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cannot archive this space'),
            content: Text(
              '${space.name} still contains in-stock items. Use, discard or move them before archiving.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(businessError(error))));
      }
      return;
    }
    await businessForm(
      context,
      title: 'Archive ${space.name}?',
      fields: const [],
      explanation:
          'This space will be hidden from active storage spaces. Inventory history will not be deleted, and the space can be restored.'
          '${space.isDefault ? '\nThe server will assign another default space or create an empty default space if needed.' : ''}',
      submit: (_) => workspace.spaceState(space.id, 'archive'),
    );
    if (!context.mounted) return;
    await controller.loadStorageSpaces();
  }

  Future<void> _setDefault(BuildContext context, StorageSpace space) async {
    final workspace = controller.workspace;
    if (workspace == null) return;
    await businessForm(
      context,
      title: 'Set ${space.name} as default?',
      fields: const [],
      explanation:
          'New stock will use this space by default. It will replace the previous default; only one space can be default.',
      submit: (_) => workspace.spaceState(space.id, 'default'),
    );
    if (context.mounted) await controller.loadStorageSpaces();
  }

  Future<void> _restore(BuildContext context) async {
    final workspace = controller.workspace!;
    try {
      final spaces = await workspace.choices(
        'storage-spaces',
        status: 'ARCHIVED',
      );
      if (!context.mounted) return;
      if (spaces.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No archived spaces.')));
        return;
      }
      await businessForm(
        context,
        title: 'Restore storage space',
        fields: [
          BusinessField(
            'id',
            'Archived space',
            validator: requiredValue,
            options: {
              for (final s in spaces) s['id'] as String: s['name'] as String,
            },
          ),
        ],
        submit: (values) => workspace.spaceState(values['id']!, 'restore'),
      );
      if (context.mounted) await controller.loadStorageSpaces();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(businessError(e))));
      }
    }
  }
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({
    required this.label,
    required this.icon,
    this.count,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.isDefault = false,
    this.onDefault,
  });

  final String label;
  final int? count;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isDefault;
  final VoidCallback? onDefault;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 77,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFA8D589)),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              SizedBox(width: 48, child: Icon(icon, size: 37)),
              const SizedBox(width: 10),
              Container(width: 1, height: 58, color: const Color(0xFFA8D589)),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${isDefault ? 'Default · ' : ''}${count == null ? 'Items' : '$count ${count == 1 ? 'item' : 'items'}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDefault != null || isDefault)
                IconButton(
                  onPressed: onDefault,
                  icon: AppActionIcon(
                    isDefault
                        ? ActionAssets.defaultSelected
                        : ActionAssets.defaultUnselected,
                    size: 28,
                  ),
                  tooltip: isDefault
                      ? 'Default storage space'
                      : 'Set $label as default',
                ),
              if (onEdit != null)
                IconButton(
                  onPressed: onEdit,
                  icon: const AppActionIcon(ActionAssets.edit),
                  tooltip: 'Edit $label',
                ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.archive_outlined, size: 32),
                  tooltip: 'Archive $label',
                ),
              if (onEdit == null && onTap != null)
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
