import 'package:flutter/material.dart';

import '../models/expiry_summary.dart';
import '../models/inventory_item.dart';
import '../state/expiry_summary_controller.dart';
import '../state/inventory_controller.dart';
import '../state/app_notification_controller.dart';
import '../state/storage_space_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/inventory_toolbar.dart';
import '../widgets/storage_space_picker.dart';
import '../widgets/app_bottom_navigation.dart';
import '../widgets/app_page_footer.dart';
import '../widgets/home_greeting.dart';
import '../widgets/inventory_visuals.dart';
import 'expiring_items_screen.dart';
import 'inventory_detail_screen.dart';
import 'inventory_screen.dart';
import 'notifications_screen.dart';

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
    this.notificationController,
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
  final AppNotificationController? notificationController;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: isGuest
                  ? Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(26, 30, 26, 0),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                HomeGreeting(),
                                SizedBox(height: 14),
                                _GuestHomeContent(),
                              ],
                            ),
                          ),
                        ),
                        AppPageFooter(
                          action: GuestLoginButton(onPressed: onLoginTap),
                          showLoginHint: true,
                          selectedDestination: AppNavigationDestination.home,
                          onAssistantTap: onAssistantTap,
                          onProfileTap: onProfileTap,
                        ),
                      ],
                    )
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                              26,
                              30,
                              26,
                              AppBottomNavigation.extent + 30,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(child: HomeGreeting()),
                                    const SizedBox(width: 8),
                                    ListenableBuilder(
                                      listenable:
                                          notificationController ??
                                          const _IdleListenable(),
                                      builder: (context, _) {
                                        final hasUnread =
                                            notificationController
                                                ?.notifications
                                                .isNotEmpty ??
                                            false;
                                        return IconButton(
                                          tooltip: hasUnread
                                              ? 'Notifications, unread'
                                              : 'Notifications',
                                          onPressed: () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  NotificationsScreen(
                                                    controller:
                                                        notificationController,
                                                    expiryController:
                                                        expirySummaryController,
                                                    inventoryController:
                                                        inventoryController,
                                                    storageSpaceController:
                                                        storageSpaceController,
                                                    onExpiringTap:
                                                        onExpiringTap,
                                                  ),
                                            ),
                                          ),
                                          icon: Image.asset(
                                            hasUnread
                                                ? HomeAssets.notificationUnread
                                                : HomeAssets.notificationEmpty,
                                            width: 32,
                                            height: 32,
                                            cacheWidth:
                                                (32 *
                                                        MediaQuery.devicePixelRatioOf(
                                                          context,
                                                        ))
                                                    .ceil(),
                                            excludeFromSemantics: true,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 19),
                                _UserHomeContent(
                                  expirySummaryController:
                                      expirySummaryController,
                                  inventoryController: inventoryController,
                                  storageSpaceController:
                                      storageSpaceController,
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
                          left: 0,
                          right: 0,
                          bottom: 0,
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
  const _GuestHomeContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF0E9),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFCDCDCD)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline, size: 19),
                SizedBox(width: 6),
                Text(
                  'Guest Mode',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const _SectionTitle('Expiring soon'),
        const SizedBox(height: 8),
        const Center(
          child: HomeEmptyIllustration(asset: HomeAssets.guestExpiry, size: 94),
        ),
        const SizedBox(height: 8),
        const Text(
          'No item added yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        const Text(
          'Expiry reminders will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        const _GreenDivider(),
        const SizedBox(height: 17),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: _SectionTitle('Inventory')),
            Text('0 items', style: TextStyle(fontSize: 17)),
          ],
        ),
        const SizedBox(height: 8),
        const Center(
          child: HomeEmptyIllustration(asset: HomeAssets.avatar, size: 108),
        ),
        const SizedBox(height: 7),
        const Text(
          'Your inventory is empty',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        const Text(
          'Add item to keep track of what you have.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: AppColors.muted),
        ),
        const SizedBox(height: 17),
        const _GreenDivider(),
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
  String? _selectedStorageSpaceId;

  @override
  void initState() {
    super.initState();
    final spaces = widget.storageSpaceController;
    spaces?.addListener(_onStorageSpacesChanged);
    _useOnlyStorageSpace(spaces, refreshData: false);
    if (spaces != null && spaces.status == StorageSpaceLoadStatus.initial) {
      spaces.loadStorageSpaces();
    }
    final inventory = widget.inventoryController;
    if (inventory != null && inventory.status == InventoryLoadStatus.initial) {
      inventory.loadInventory(storageSpaceId: _selectedStorageSpaceId);
    }
    final expiry = widget.expirySummaryController;
    if (expiry != null && expiry.status == ExpirySummaryLoadStatus.initial) {
      expiry.loadSummary(
        asOf: DateUtils.dateOnly(DateTime.now()),
        storageSpaceId: _selectedStorageSpaceId,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _UserHomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storageSpaceController == widget.storageSpaceController) {
      return;
    }
    oldWidget.storageSpaceController?.removeListener(_onStorageSpacesChanged);
    widget.storageSpaceController?.addListener(_onStorageSpacesChanged);
    _useOnlyStorageSpace(widget.storageSpaceController);
  }

  @override
  void dispose() {
    widget.storageSpaceController?.removeListener(_onStorageSpacesChanged);
    super.dispose();
  }

  void _onStorageSpacesChanged() {
    _useOnlyStorageSpace(widget.storageSpaceController);
  }

  void _useOnlyStorageSpace(
    StorageSpaceController? controller, {
    bool refreshData = true,
  }) {
    if (controller?.status != StorageSpaceLoadStatus.loaded ||
        controller!.storageSpaces.length != 1) {
      return;
    }

    final onlySpaceId = controller.storageSpaces.single.id;
    if (_selectedStorageSpaceId == onlySpaceId) return;

    if (mounted) {
      setState(() => _selectedStorageSpaceId = onlySpaceId);
    } else {
      _selectedStorageSpaceId = onlySpaceId;
    }

    if (!refreshData) return;
    widget.inventoryController?.loadInventory(storageSpaceId: onlySpaceId);
    widget.expirySummaryController?.loadSummary(
      asOf: DateUtils.dateOnly(DateTime.now()),
      storageSpaceId: onlySpaceId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InventoryToolbar(
          storagePicker: StoragePickerButton(
            label: _selectedStorageSpaceId == null
                ? 'All Spaces'
                : {
                        for (final space
                            in widget.storageSpaceController?.storageSpaces ??
                                const [])
                          space.id: space.name,
                      }[_selectedStorageSpaceId] ??
                      'Selected space',
            onTap: _openStorageSpaces,
          ),
          onSearch: widget.onSearchTap ?? _openSearch,
        ),
        const SizedBox(height: 42),
        const _SectionTitle('Expiring soon'),
        const SizedBox(height: 15),
        AnimatedBuilder(
          animation: widget.expirySummaryController ?? const _IdleListenable(),
          builder: (context, child) => _buildExpirySummary(),
        ),
        AnimatedBuilder(
          animation: widget.expirySummaryController ?? const _IdleListenable(),
          builder: (context, child) {
            final controller = widget.expirySummaryController;
            if (controller?.status != ExpirySummaryLoadStatus.loaded ||
                controller!.counts.total == 0) {
              return const SizedBox(height: 32);
            }
            return Column(
              children: [
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: _GreenAction(
                    label: 'View all expiring items',
                    onPressed: _openExpiringItems,
                  ),
                ),
                const SizedBox(height: 38),
              ],
            );
          },
        ),
        AnimatedBuilder(
          animation: widget.inventoryController ?? const _IdleListenable(),
          builder: (context, child) => _buildInventorySummary(),
        ),
        const SizedBox(height: 23),
        Align(
          alignment: Alignment.centerLeft,
          child: _GreenAction(
            label: 'View all items',
            onPressed: _openInventory,
            width: 238,
          ),
        ),
      ],
    );
  }

  Widget _buildExpirySummary() {
    final controller = widget.expirySummaryController;
    if (controller == null) {
      return const _StatusMessage('Expiry data unavailable.');
    }
    return switch (controller.status) {
      ExpirySummaryLoadStatus.initial ||
      ExpirySummaryLoadStatus.loading => const SizedBox(
        height: 135,
        child: Center(child: CircularProgressIndicator()),
      ),
      ExpirySummaryLoadStatus.error => _StatusMessage(
        controller.errorMessage ?? 'Unable to load expiry data.',
        onRetry: controller.reload,
      ),
      ExpirySummaryLoadStatus.empty => const _EmptyExpiry(),
      ExpirySummaryLoadStatus.loaded =>
        controller.counts.total == 0
            ? const _EmptyExpiry()
            : Row(
                children: [
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width < 360 ? 76 : 100,
                    child: Column(
                      children: [
                        Text(
                          '${controller.counts.total}',
                          style: const TextStyle(
                            color: Color(0xFFC8532C),
                            fontSize: 77,
                            height: 0.95,
                          ),
                        ),
                        const Text(
                          'Items',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 128,
                    color: const Color(0xFFA8D589),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      children: [
                        for (
                          var i = 0;
                          i < controller.items.length && i < 2;
                          i++
                        ) ...[
                          if (i > 0)
                            const Divider(color: Color(0xFFA8D589), height: 13),
                          _ExpiryPreviewRow(
                            summaryItem: controller.items[i],
                            onTap: () => _openDetail(controller.items[i].item),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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
            const Expanded(child: _SectionTitle('Inventory')),
            Text(
              '$total ${total == 1 ? 'item' : 'items'}',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 48,
              height: 32,
              child: FilledButton(
                onPressed: widget.onAddItemTap,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Icon(
                  Icons.add,
                  size: 23,
                  semanticLabel: 'Add inventory',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        switch (status) {
          InventoryLoadStatus.initial ||
          InventoryLoadStatus.loading => const SizedBox(
            height: 92,
            child: Center(child: CircularProgressIndicator()),
          ),
          InventoryLoadStatus.error => _StatusMessage(
            controller?.errorMessage ?? 'Unable to load inventory.',
            onRetry: controller?.reload,
          ),
          InventoryLoadStatus.empty => Column(
            children: [
              Image.asset(HomeAssets.avatar, width: 96, height: 96),
              const SizedBox(height: 8),
              const Text(
                'Your inventory is empty',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              const Text(
                'Add item to keep track of what you have.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: AppColors.muted),
              ),
            ],
          ),
          InventoryLoadStatus.loaded => _CategoryCounts(
            items: controller!.items,
            partial: controller.hasNextPage,
            onSelected: (group) => _openInventory(group: group),
          ),
        },
      ],
    );
  }

  void _openStorageSpaces() {
    final custom = widget.onStorageSpacesTap;
    if (custom != null) {
      custom();
      return;
    }
    final controller = widget.storageSpaceController;
    if (controller == null) return;
    showStorageSpacePicker(
      context,
      selectedId: _selectedStorageSpaceId,
      spacesController: controller,
      inventoryController: widget.inventoryController,
      onSelected: _selectStorageSpace,
    );
  }

  void _selectStorageSpace(String? id) {
    setState(() => _selectedStorageSpaceId = id);
    widget.inventoryController?.loadInventory(storageSpaceId: id);
    widget.expirySummaryController?.loadSummary(
      asOf: DateUtils.dateOnly(DateTime.now()),
      storageSpaceId: id,
    );
  }

  Future<void> _openSearch() async {
    final controller = widget.inventoryController;
    if (controller == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventorySearchScreen(
          controller: controller,
          storageSpaceController: widget.storageSpaceController,
        ),
      ),
    );
    if (mounted) {
      controller.loadInventory(storageSpaceId: _selectedStorageSpaceId);
    }
  }

  Future<void> _openInventory({InventoryCategoryGroup? group}) async {
    final custom = widget.onInventoryTap;
    if (custom != null) {
      custom();
      return;
    }
    final controller = widget.inventoryController;
    if (controller == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryScreen(
          controller: controller,
          storageSpaceController: widget.storageSpaceController,
          onAddItemTap: widget.onAddItemTap,
          initialCategoryGroup: group,
        ),
      ),
    );
    if (mounted) {
      controller.loadInventory(storageSpaceId: _selectedStorageSpaceId);
    }
  }

  Future<void> _openExpiringItems() async {
    final custom = widget.onExpiringTap;
    if (custom != null) {
      custom();
      return;
    }
    final expiry = widget.expirySummaryController;
    final inventory = widget.inventoryController;
    if (expiry == null || inventory == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpiringItemsScreen(
          controller: expiry,
          inventoryController: inventory,
          storageSpaceController: widget.storageSpaceController,
        ),
      ),
    );
    if (mounted) {
      expiry.loadSummary(
        asOf: DateUtils.dateOnly(DateTime.now()),
        storageSpaceId: _selectedStorageSpaceId,
      );
      inventory.loadInventory(storageSpaceId: _selectedStorageSpaceId);
    }
  }

  void _openDetail(InventoryItem item) {
    final inventory = widget.inventoryController;
    if (inventory == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryDetailScreen(
          itemId: item.id,
          controller: inventory.createDetailController(),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
  );
}

class _GreenDivider extends StatelessWidget {
  const _GreenDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(color: Color(0xFFA8D589), thickness: 0.8, height: 1);
}

class _GreenAction extends StatelessWidget {
  const _GreenAction({
    required this.label,
    required this.onPressed,
    this.width,
  });

  final String label;
  final VoidCallback onPressed;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 45,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

class _EmptyExpiry extends StatelessWidget {
  const _EmptyExpiry();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Image.asset(HomeAssets.noExpiry, width: 105, height: 105),
          const SizedBox(height: 9),
          const Text(
            'No items expiring soon',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 9),
          const Text(
            'Nothing is due to expire\nin the next 3 days',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ExpiryPreviewRow extends StatelessWidget {
  const _ExpiryPreviewRow({required this.summaryItem, required this.onTap});
  final ExpirySummaryItem summaryItem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = summaryItem.item;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Row(
          children: [
            InventoryArtwork(item: item, size: 43),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemDefinitionName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.2),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: quantityLabel(item),
                          style: TextStyle(
                            color: item.isEstimated
                                ? const Color(0xFFD75A20)
                                : const Color(0xFF388D38),
                          ),
                        ),
                        TextSpan(
                          text: ' | ${item.storageSpaceName}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 68,
              child: Text(
                expiryLabel(item.expiryDate),
                maxLines: 2,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: expiryColor(item.expiryDate),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCounts extends StatelessWidget {
  const _CategoryCounts({
    required this.items,
    required this.partial,
    required this.onSelected,
  });

  final List<InventoryItem> items;
  final bool partial;
  final ValueChanged<InventoryCategoryGroup> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final group in InventoryCategoryGroup.values) ...[
          if (group != InventoryCategoryGroup.meat)
            Container(width: 1, height: 78, color: const Color(0xFFA8D589)),
          Expanded(
            child: InkWell(
              key: ValueKey('inventory-group-${group.name}'),
              onTap: () => onSelected(group),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(
                      '${items.where(group.includes).length}${partial ? '+' : ''}',
                      style: const TextStyle(fontSize: 40, height: 1.1),
                    ),
                    Text(
                      group.label,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage(this.message, {this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 115,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
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
