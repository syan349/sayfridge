import 'package:flutter/material.dart';

import '../models/expiry_summary.dart';
import '../models/inventory_item.dart';
import '../models/storage_space.dart';
import '../state/expiry_summary_controller.dart';
import '../state/inventory_controller.dart';
import '../state/storage_space_controller.dart';
import '../widgets/app_background.dart';
import '../widgets/app_bottom_navigation.dart';
import 'expiring_items_screen.dart';
import 'inventory_screen.dart';
import 'storage_space_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onAssistantTap,
    this.expirySummaryController,
    this.inventoryController,
    this.storageSpaceController,
    this.onProfileTap,
    this.onLoginTap,
    this.onStorageSpacesTap,
    this.onSearchTap,
    this.onExpiringTap,
    this.onInventoryTap,
    this.onAddItemTap,
    this.isGuest = false,
    super.key,
  });

  final VoidCallback onAssistantTap;
  final ExpirySummaryController? expirySummaryController;
  final InventoryController? inventoryController;
  final StorageSpaceController? storageSpaceController;
  final VoidCallback? onProfileTap;
  final VoidCallback? onLoginTap;
  final VoidCallback? onStorageSpacesTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onExpiringTap;
  final VoidCallback? onInventoryTap;
  final VoidCallback? onAddItemTap;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(25, 40, 25, 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Good afternoon!',
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          const SizedBox(height: 32),
                          Text(
                            isGuest ? 'Guest Mode' : 'All Spaces',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 32),
                          if (isGuest)
                            _GuestHomeContent(onLoginTap: onLoginTap)
                          else
                            _UserHomeContent(
                              expirySummaryController: expirySummaryController,
                              inventoryController: inventoryController,
                              storageSpaceController: storageSpaceController,
                              onStorageSpacesTap: onStorageSpacesTap,
                              onSearchTap: onSearchTap,
                              onExpiringTap: onExpiringTap,
                              onInventoryTap: onInventoryTap,
                              onAddItemTap: onAddItemTap,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 35,
                    right: 35,
                    bottom: 4,
                    child: AppBottomNavigation(
                      selectedDestination: AppNavigationDestination.home,
                      onAssistantTap: onAssistantTap,
                      onProfileTap: onProfileTap,
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
}

class _GuestHomeContent extends StatelessWidget {
  const _GuestHomeContent({required this.onLoginTap});

  final VoidCallback? onLoginTap;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Expiring soon',
          style: TextStyle(fontSize: 29, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 22),
        Icon(Icons.calendar_month_outlined, size: 72, color: primaryColor),
        const SizedBox(height: 14),
        const Text(
          'No item added yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Expiry reminders will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
        const SizedBox(height: 28),
        Divider(color: primaryColor),
        const SizedBox(height: 24),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Inventory',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w500),
            ),
            Text('0 items', style: TextStyle(fontSize: 21)),
          ],
        ),
        const SizedBox(height: 22),
        Icon(Icons.kitchen_outlined, size: 76, color: primaryColor),
        const SizedBox(height: 12),
        const Text(
          'Your inventory is empty',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add items to keep track of what you have.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
        const SizedBox(height: 28),
        const Text(
          'Log in to start your own inventory.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: onLoginTap,
            child: const Text(
              'Log in / Sign up',
              style: TextStyle(fontSize: 19),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserHomeContent extends StatefulWidget {
  const _UserHomeContent({
    required this.expirySummaryController,
    required this.inventoryController,
    required this.storageSpaceController,
    required this.onStorageSpacesTap,
    required this.onSearchTap,
    required this.onExpiringTap,
    required this.onInventoryTap,
    required this.onAddItemTap,
  });

  final ExpirySummaryController? expirySummaryController;
  final InventoryController? inventoryController;
  final StorageSpaceController? storageSpaceController;
  final VoidCallback? onStorageSpacesTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onExpiringTap;
  final VoidCallback? onInventoryTap;
  final VoidCallback? onAddItemTap;

  @override
  State<_UserHomeContent> createState() => _UserHomeContentState();
}

class _UserHomeContentState extends State<_UserHomeContent> {
  StorageSpace? _selectedStorageSpace;

  @override
  void initState() {
    super.initState();

    final controller = widget.storageSpaceController;
    if (controller != null &&
        controller.status == StorageSpaceLoadStatus.initial) {
      controller.loadStorageSpaces();
    }

    final inventoryController = widget.inventoryController;
    if (inventoryController != null &&
        inventoryController.status == InventoryLoadStatus.initial) {
      inventoryController.loadInventory();
    }

    final expirySummaryController = widget.expirySummaryController;
    if (expirySummaryController != null &&
        expirySummaryController.status == ExpirySummaryLoadStatus.initial) {
      expirySummaryController.loadSummary(
        asOf: DateUtils.dateOnly(DateTime.now()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _openStorageSpaces,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  backgroundColor: Colors.white,
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                child: AnimatedBuilder(
                  animation:
                      widget.storageSpaceController ?? const _IdleListenable(),
                  builder: (context, child) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: Text(_storageSpaceLabel)),
                      const Icon(Icons.keyboard_arrow_down),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: widget.onSearchTap ?? _openInventory,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search, size: 26),
                      SizedBox(width: 10),
                      Text(
                        'Search items ...',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 42),
        const Text(
          'Expiring soon',
          style: TextStyle(fontSize: 29, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 24),
        AnimatedBuilder(
          animation: widget.expirySummaryController ?? const _IdleListenable(),
          builder: (context, child) => _buildExpirySummary(primaryColor),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _openExpiringItems,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right),
            label: const Text('View all expiring items'),
          ),
        ),
        const SizedBox(height: 50),
        AnimatedBuilder(
          animation: widget.inventoryController ?? const _IdleListenable(),
          builder: (context, child) => _buildInventorySummary(),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: 260,
          child: FilledButton.icon(
            onPressed: _openInventory,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right),
            label: const Text('View all items'),
          ),
        ),
      ],
    );
  }

  String get _storageSpaceLabel {
    final controller = widget.storageSpaceController;
    if (controller == null) return 'All Spaces';

    final selectedStorageSpace = _selectedStorageSpace;
    if (selectedStorageSpace != null) return selectedStorageSpace.name;

    return switch (controller.status) {
      StorageSpaceLoadStatus.initial => 'All Spaces',
      StorageSpaceLoadStatus.loading => 'Loading...',
      StorageSpaceLoadStatus.loaded => 'All Spaces (${controller.total})',
      StorageSpaceLoadStatus.empty => 'No spaces',
      StorageSpaceLoadStatus.error => 'Try again',
    };
  }

  Widget _buildExpirySummary(Color primaryColor) {
    final controller = widget.expirySummaryController;
    if (controller == null) {
      return const _ExpiryStatusMessage(message: 'Expiry data unavailable.');
    }

    return switch (controller.status) {
      ExpirySummaryLoadStatus.initial ||
      ExpirySummaryLoadStatus.loading => const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      ),
      ExpirySummaryLoadStatus.empty => const _ExpiryCountAndContent(
        count: 0,
        child: _ExpiryStatusMessage(message: 'No items expiring soon.'),
      ),
      ExpirySummaryLoadStatus.error => _ExpiryCountAndContent(
        count: 0,
        child: _ExpiryStatusMessage(
          message: controller.errorMessage ?? 'Unable to load expiry data.',
          onRetry: controller.reload,
        ),
      ),
      ExpirySummaryLoadStatus.loaded => _ExpiryCountAndContent(
        count: controller.counts.total,
        dividerColor: primaryColor,
        child: Column(
          children: [
            for (
              var index = 0;
              index < controller.items.length && index < 2;
              index++
            ) ...[
              if (index > 0) const Divider(),
              _ExpiryItemRow(summaryItem: controller.items[index]),
            ],
          ],
        ),
      ),
    };
  }

  Widget _buildInventorySummary() {
    final controller = widget.inventoryController;
    final status = controller?.status ?? InventoryLoadStatus.initial;
    final total = status == InventoryLoadStatus.loaded ? controller!.total : 0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Inventory',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w500),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$total ${total == 1 ? 'item' : 'items'}',
                  style: const TextStyle(fontSize: 21),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: widget.onAddItemTap,
                  tooltip: 'Add inventory item',
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 28),
        switch (status) {
          InventoryLoadStatus.initial ||
          InventoryLoadStatus.loading => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          InventoryLoadStatus.empty => const _InventoryStatusMessage(
            icon: Icons.inventory_2_outlined,
            message: 'Your inventory is empty.',
          ),
          InventoryLoadStatus.error => _InventoryStatusMessage(
            icon: Icons.cloud_off_outlined,
            message: controller?.errorMessage ?? 'Unable to load inventory.',
            onRetry: controller?.reload,
          ),
          InventoryLoadStatus.loaded => _InventoryPreview(
            items: controller!.items.take(3).toList(growable: false),
          ),
        },
      ],
    );
  }

  void _openStorageSpaces() {
    final customAction = widget.onStorageSpacesTap;
    if (customAction != null) {
      customAction();
      return;
    }

    final controller = widget.storageSpaceController;
    if (controller == null) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (storageContext) => StorageSpaceScreen(
          controller: controller,
          onSelected: (space) {
            Navigator.of(storageContext).pop();
            _selectStorageSpace(space);
          },
        ),
      ),
    );
  }

  void _selectStorageSpace(StorageSpace? space) {
    setState(() {
      _selectedStorageSpace = space;
    });

    widget.inventoryController?.loadInventory(storageSpaceId: space?.id);
    widget.expirySummaryController?.loadSummary(
      asOf: DateUtils.dateOnly(DateTime.now()),
      storageSpaceId: space?.id,
    );
  }

  void _openInventory() {
    final customAction = widget.onInventoryTap;
    if (customAction != null) {
      customAction();
      return;
    }

    final controller = widget.inventoryController;
    if (controller == null) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryScreen(controller: controller),
      ),
    );
  }

  void _openExpiringItems() {
    final customAction = widget.onExpiringTap;
    if (customAction != null) {
      customAction();
      return;
    }

    final expiryController = widget.expirySummaryController;
    final inventoryController = widget.inventoryController;
    if (expiryController == null || inventoryController == null) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpiringItemsScreen(
          controller: expiryController,
          inventoryController: inventoryController,
        ),
      ),
    );
  }
}

class _IdleListenable implements Listenable {
  const _IdleListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class _ExpiryCountAndContent extends StatelessWidget {
  const _ExpiryCountAndContent({
    required this.count,
    required this.child,
    this.dividerColor,
  });

  final int count;
  final Widget child;
  final Color? dividerColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          child: Column(
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  color: Color(0xFFD95228),
                  fontSize: 78,
                  height: 0.9,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                count == 1 ? 'Item' : 'Items',
                style: const TextStyle(color: Colors.grey, fontSize: 20),
              ),
            ],
          ),
        ),
        Container(
          width: 1,
          height: 150,
          color: dividerColor ?? Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 16),
        Expanded(child: child),
      ],
    );
  }
}

class _ExpiryItemRow extends StatelessWidget {
  const _ExpiryItemRow({required this.summaryItem});

  final ExpirySummaryItem summaryItem;

  @override
  Widget build(BuildContext context) {
    final item = summaryItem.item;

    return Row(
      children: [
        const Icon(Icons.inventory_2_outlined, size: 42),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.itemDefinitionName,
                style: const TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 3),
              Text(
                '${item.displayQuantity} | ${item.storageSpaceName}',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
        Text(
          _bucketLabel(summaryItem.bucket),
          style: const TextStyle(color: Color(0xFFC66500), fontSize: 14),
        ),
      ],
    );
  }

  String _bucketLabel(String bucket) {
    return switch (bucket) {
      'overdue' => 'Overdue',
      'today' => 'Today',
      'upcoming' => 'Soon',
      _ => bucket,
    };
  }
}

class _ExpiryStatusMessage extends StatelessWidget {
  const _ExpiryStatusMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(message, textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ],
    );
  }
}

class _InventoryPreview extends StatelessWidget {
  const _InventoryPreview({required this.items});

  final List<InventoryItem> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items
          .map(
            (item) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 34),
                    const SizedBox(height: 8),
                    Text(
                      item.itemDefinitionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.displayQuantity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _InventoryStatusMessage extends StatelessWidget {
  const _InventoryStatusMessage({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Flexible(child: Text(message)),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
