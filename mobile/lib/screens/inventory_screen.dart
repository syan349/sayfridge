import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/page_scroll_fade.dart';

import '../models/inventory_item.dart';
import '../state/inventory_controller.dart';
import '../state/storage_space_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/inventory_toolbar.dart';
import '../widgets/storage_space_picker.dart';
import '../widgets/inventory_visuals.dart';
import 'inventory_detail_screen.dart';

enum InventoryCategoryGroup { meat, vegetables, others }

extension InventoryCategoryGroupDetails on InventoryCategoryGroup {
  String get label => switch (this) {
    InventoryCategoryGroup.meat => 'Meat',
    InventoryCategoryGroup.vegetables => 'Vegetables',
    InventoryCategoryGroup.others => 'Others',
  };

  bool includes(InventoryItem item) {
    final category = item.categoryName.toLowerCase();
    final isMeat =
        category.contains('meat') ||
        category.contains('poultry') ||
        category.contains('seafood');
    final isVegetable =
        category.contains('vegetable') || category.contains('produce');
    return switch (this) {
      InventoryCategoryGroup.meat => isMeat,
      InventoryCategoryGroup.vegetables => isVegetable,
      InventoryCategoryGroup.others => !isMeat && !isVegetable,
    };
  }
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    required this.controller,
    this.storageSpaceController,
    this.onAddItemTap,
    this.initialCategoryGroup,
    super.key,
  });

  final InventoryController controller;
  final StorageSpaceController? storageSpaceController;
  final VoidCallback? onAddItemTap;
  final InventoryCategoryGroup? initialCategoryGroup;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String? _selectedCategoryId;
  late InventoryCategoryGroup? _selectedGroup;

  @override
  void initState() {
    super.initState();
    _selectedGroup = widget.initialCategoryGroup;
    if (_selectedGroup != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.loadInventory(
          storageSpaceId: widget.controller.storageSpaceId,
          pageSize: 100,
        );
      });
    }
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
                  OverviewHeader(
                    title: _selectedGroup == null
                        ? 'Inventory Overview'
                        : _selectedGroup!.label,
                  ),
                  if (widget.onAddItemTap != null)
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add inventory'),
                      onPressed: widget.onAddItemTap,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(25, 8, 25, 13),
                    child: InventoryToolbar(
                      storagePicker: _StoragePill(
                        controller: widget.controller,
                        spacesController: widget.storageSpaceController,
                        pageSize: _selectedGroup == null ? 20 : 100,
                      ),
                      onSearch: _openSearch,
                      onFilter: _showFilter,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(25, 0, 25, 8),
                    child: QuantityLegend(),
                  ),
                  Expanded(
                    child: PageScrollFade(
                      child: AnimatedBuilder(
                        animation: widget.controller,
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
    final controller = widget.controller;
    final groupedItems = _selectedGroup == null
        ? controller.items
        : controller.items.where(_selectedGroup!.includes).toList();
    return switch (controller.status) {
      InventoryLoadStatus.initial || InventoryLoadStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      InventoryLoadStatus.empty => _InventoryMessage(
        title: controller.query.isEmpty
            ? 'Your inventory is empty'
            : 'No matching items',
        message: controller.query.isEmpty
            ? 'Add item to keep track of what you have.'
            : 'Try a different search term.',
        onAction: controller.reload,
      ),
      InventoryLoadStatus.error => _InventoryMessage(
        title: 'Unable to load inventory',
        message: controller.errorMessage ?? 'Please try again.',
        onAction: controller.reload,
      ),
      InventoryLoadStatus.loaded =>
        groupedItems.isEmpty
            ? _InventoryMessage(
                title: 'No ${_selectedGroup!.label.toLowerCase()} items',
                message: 'There are no items in this category group.',
                onAction: controller.reload,
              )
            : _InventoryResults(
                controller: controller,
                items: groupedItems,
                showPagination: _selectedGroup == null,
                onOpenDetails: _openDetails,
              ),
    };
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventorySearchScreen(
          controller: widget.controller,
          storageSpaceController: widget.storageSpaceController,
        ),
      ),
    );
    if (mounted) {
      widget.controller.loadInventory(
        storageSpaceId: widget.controller.storageSpaceId,
        categoryId: _selectedCategoryId,
      );
    }
  }

  void _showFilter() {
    final items = widget.controller.items;
    final categories = <String, String>{};
    for (final item in items) {
      categories[item.categoryId] = item.categoryName;
    }
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
                'Filter by category',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: const Text('All categories'),
                trailing: Icon(
                  _selectedCategoryId == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onTap: () => _applyCategory(sheetContext, null),
              ),
              for (final category in categories.entries)
                ListTile(
                  title: Text(category.value),
                  trailing: Icon(
                    _selectedCategoryId == category.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: () => _applyCategory(sheetContext, category.key),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyCategory(BuildContext sheetContext, String? categoryId) {
    Navigator.pop(sheetContext);
    setState(() {
      _selectedCategoryId = categoryId;
      _selectedGroup = null;
    });
    widget.controller.loadInventory(
      storageSpaceId: widget.controller.storageSpaceId,
      categoryId: categoryId,
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

class InventorySearchScreen extends StatefulWidget {
  const InventorySearchScreen({
    required this.controller,
    this.storageSpaceController,
    super.key,
  });

  final InventoryController controller;
  final StorageSpaceController? storageSpaceController;

  @override
  State<InventorySearchScreen> createState() => _InventorySearchScreenState();
}

class _InventorySearchScreenState extends State<InventorySearchScreen> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.controller.query);
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
                  const OverviewHeader(title: 'Search'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(25, 5, 25, 17),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      onChanged: _onChanged,
                      onSubmitted: _search,
                      decoration: InputDecoration(
                        hintText: 'Search items ...',
                        prefixIcon: Center(
                          widthFactor: 1,
                          heightFactor: 1,
                          child: Image.asset(
                            HomeAssets.search,
                            width: 25,
                            height: 25,
                          ),
                        ),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: _clear,
                                icon: const Icon(
                                  Icons.cancel,
                                  color: AppColors.muted,
                                ),
                              ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(25, 0, 25, 13),
                    child: Row(
                      children: [
                        const Text(
                          'Search in',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _StoragePill(
                                controller: widget.controller,
                                spacesController: widget.storageSpaceController,
                              ),
                            ),
                          ),
                        ),
                        AnimatedBuilder(
                          animation: widget.controller,
                          builder: (context, child) => Text(
                            '${widget.controller.total} items',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageScrollFade(
                      child: AnimatedBuilder(
                        animation: widget.controller,
                        builder: (context, child) {
                          final controller = widget.controller;
                          if (controller.status ==
                              InventoryLoadStatus.loading) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (controller.status == InventoryLoadStatus.error) {
                            return _InventoryMessage(
                              title: 'Unable to search',
                              message:
                                  controller.errorMessage ??
                                  'Please try again.',
                              onAction: controller.reload,
                            );
                          }
                          if (controller.status == InventoryLoadStatus.empty) {
                            return const Center(
                              child: Text('No matching items'),
                            );
                          }
                          return _InventoryResults(
                            controller: controller,
                            onOpenDetails: (item) => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => InventoryDetailScreen(
                                  itemId: item.id,
                                  controller: controller
                                      .createDetailController(),
                                ),
                              ),
                            ),
                          );
                        },
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

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  void _search(String value) {
    widget.controller.loadInventory(
      query: value.trim(),
      storageSpaceId: widget.controller.storageSpaceId,
    );
  }

  void _clear() {
    _searchController.clear();
    _onChanged('');
  }
}

class _StoragePill extends StatelessWidget {
  const _StoragePill({
    required this.controller,
    this.spacesController,
    this.pageSize = 20,
  });
  final InventoryController controller;
  final StorageSpaceController? spacesController;
  final int pageSize;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, spacesController]),
    builder: (context, _) {
      final spaces = <String, String>{};
      for (final item in controller.items) {
        spaces[item.storageSpaceId] = item.storageSpaceName;
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
          inventoryController: controller,
          onSelected: (id) => controller.loadInventory(
            query: controller.query,
            storageSpaceId: id,
            pageSize: pageSize,
          ),
        ),
      );
    },
  );
}

class _InventoryResults extends StatelessWidget {
  const _InventoryResults({
    required this.controller,
    required this.onOpenDetails,
    this.items,
    this.showPagination = true,
  });

  final InventoryController controller;
  final ValueChanged<InventoryItem> onOpenDetails;
  final List<InventoryItem>? items;
  final bool showPagination;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(25, 8, 25, 32),
        children: [
          for (final item in items ?? controller.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: InventoryItemTile(
                item: item,
                onTap: () => onOpenDetails(item),
              ),
            ),
          if (showPagination && (controller.page > 1 || controller.hasNextPage))
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: controller.page > 1
                      ? () => _loadPage(controller.page - 1)
                      : null,
                  child: const Text('Previous'),
                ),
                Text('Page ${controller.page}'),
                TextButton(
                  onPressed: controller.hasNextPage
                      ? () => _loadPage(controller.page + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _loadPage(int page) {
    controller.loadInventory(
      status: controller.inventoryStatus,
      query: controller.query,
      storageSpaceId: controller.storageSpaceId,
      page: page,
      pageSize: controller.pageSize,
    );
  }
}

class _InventoryMessage extends StatelessWidget {
  const _InventoryMessage({
    required this.title,
    required this.message,
    required this.onAction,
  });

  final String title;
  final String message;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(HomeAssets.avatar, width: 104, height: 104),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: const Text('Refresh')),
          ],
        ),
      ),
    );
  }
}
