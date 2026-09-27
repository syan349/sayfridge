import 'package:flutter/material.dart';

import '../models/expiry_summary.dart';
import '../models/inventory_item.dart';
import '../models/storage_space.dart';
import '../state/expiry_summary_controller.dart';
import '../state/inventory_controller.dart';
import '../state/storage_space_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_bottom_navigation.dart';
import '../widgets/app_page_footer.dart';
import '../widgets/home_greeting.dart';
import '../widgets/inventory_visuals.dart';
import 'expiring_items_screen.dart';
import 'inventory_detail_screen.dart';
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
                                const HomeGreeting(),
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
  StorageSpace? _selectedStorageSpace;

  @override
  void initState() {
    super.initState();
    final spaces = widget.storageSpaceController;
    if (spaces != null && spaces.status == StorageSpaceLoadStatus.initial) {
      spaces.loadStorageSpaces();
    }
    final inventory = widget.inventoryController;
    if (inventory != null && inventory.status == InventoryLoadStatus.initial) {
      inventory.loadInventory();
    }
    final expiry = widget.expirySummaryController;
    if (expiry != null && expiry.status == ExpirySummaryLoadStatus.initial) {
      expiry.loadSummary(asOf: DateUtils.dateOnly(DateTime.now()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _HomePill(
              onTap: _openStorageSpaces,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 105),
                    child: Text(
                      _selectedStorageSpace?.name ?? 'All Spaces',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down, size: 21),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _HomePill(
                onTap: widget.onSearchTap ?? _openSearch,
                child: Row(
                  children: [
                    Image.asset(HomeAssets.search, width: 21, height: 21),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Search items ...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
                    width: 112,
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
              style: const TextStyle(fontSize: 17),
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 11, 20, 28),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, child) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 58,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.muted,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Choose storage space',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 15),
                _spaceOption(
                  sheetContext,
                  null,
                  'All spaces',
                  widget.inventoryController?.storageSpaceId == null
                      ? widget.inventoryController?.total
                      : null,
                ),
                if (controller.status == StorageSpaceLoadStatus.loading)
                  const Center(child: CircularProgressIndicator()),
                if (controller.status == StorageSpaceLoadStatus.error)
                  TextButton(
                    onPressed: controller.loadStorageSpaces,
                    child: const Text('Could not load spaces. Try again'),
                  ),
                for (final space in controller.storageSpaces)
                  _spaceOption(
                    sheetContext,
                    space,
                    space.name,
                    _countForSpace(space),
                  ),
                const Divider(color: Color(0xFFA8D589)),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 5),
                  leading: Image.asset(
                    HomeAssets.setting,
                    width: 26,
                    height: 26,
                  ),
                  title: const Text(
                    'Manage storage spaces',
                    style: TextStyle(fontSize: 17),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => StorageSpaceScreen(
                          controller: controller,
                          inventoryController: widget.inventoryController,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _spaceOption(
    BuildContext sheetContext,
    StorageSpace? space,
    String label,
    int? count,
  ) {
    final selected = _selectedStorageSpace?.id == space?.id;
    return InkWell(
      onTap: () {
        Navigator.pop(sheetContext);
        _selectStorageSpace(space);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE1F5D2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    count == null
                        ? 'Items'
                        : '$count ${count == 1 ? 'item' : 'items'}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: Colors.black,
            ),
          ],
        ),
      ),
    );
  }

  int? _countForSpace(StorageSpace space) {
    final inventory = widget.inventoryController;
    if (inventory == null || inventory.status != InventoryLoadStatus.loaded) {
      return null;
    }
    if (inventory.hasNextPage || inventory.storageSpaceId != null) return null;
    return inventory.items
        .where((item) => item.storageSpaceId == space.id)
        .length;
  }

  void _selectStorageSpace(StorageSpace? space) {
    setState(() => _selectedStorageSpace = space);
    widget.inventoryController?.loadInventory(storageSpaceId: space?.id);
    widget.expirySummaryController?.loadSummary(
      asOf: DateUtils.dateOnly(DateTime.now()),
      storageSpaceId: space?.id,
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
      controller.loadInventory(storageSpaceId: _selectedStorageSpace?.id);
    }
  }

  Future<void> _openInventory() async {
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
        ),
      ),
    );
    if (mounted) {
      controller.loadInventory(storageSpaceId: _selectedStorageSpace?.id);
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
        storageSpaceId: _selectedStorageSpace?.id,
      );
      inventory.loadInventory(storageSpaceId: _selectedStorageSpace?.id);
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

class _HomePill extends StatelessWidget {
  const _HomePill({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 37,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE6EDDF)),
            borderRadius: BorderRadius.circular(28),
          ),
          child: child,
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
      child: Row(
        children: [
          InventoryArtwork(item: item, size: 47),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemDefinitionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
                Text(
                  '${quantityLabel(item)} | ${item.storageSpaceName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: item.isEstimated
                        ? const Color(0xFFD75A20)
                        : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              expiryLabel(item.expiryDate),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: expiryColor(item.expiryDate),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCounts extends StatelessWidget {
  const _CategoryCounts({required this.items, required this.partial});

  final List<InventoryItem> items;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    int count(String group) => items.where((item) {
      final category = item.categoryName.toLowerCase();
      if (group == 'Meat') {
        return category.contains('meat') ||
            category.contains('poultry') ||
            category.contains('seafood');
      }
      if (group == 'Vegetables') {
        return category.contains('vegetable') || category.contains('produce');
      }
      return !category.contains('meat') &&
          !category.contains('poultry') &&
          !category.contains('seafood') &&
          !category.contains('vegetable') &&
          !category.contains('produce');
    }).length;

    return Row(
      children: [
        for (final group in const ['Meat', 'Vegetables', 'Others']) ...[
          if (group != 'Meat')
            Container(width: 1, height: 78, color: const Color(0xFFA8D589)),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${count(group)}${partial ? '+' : ''}',
                  style: const TextStyle(fontSize: 40, height: 1.1),
                ),
                Text(
                  group,
                  style: const TextStyle(fontSize: 15, color: AppColors.muted),
                ),
              ],
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
