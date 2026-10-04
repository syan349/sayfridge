import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/app_dialog.dart';
import '../widgets/app_action_icon.dart';

import '../widgets/page_scroll_fade.dart';

import '../models/inventory_item.dart';
import '../repositories/workspace_repository.dart';
import '../state/inventory_controller.dart';
import '../state/storage_space_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/inventory_toolbar.dart';
import '../widgets/storage_space_picker.dart';
import '../widgets/inventory_visuals.dart';
import '../widgets/swipe_delete_card.dart';
import '../widgets/selection_sheet.dart';
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
  final Map<String, InventoryItem> _selected = {};
  bool _deleteMode = false, _deleting = false, _confirmingDelete = false;
  bool _selecting = false;
  int _selectionRequest = 0;
  List<InventoryItem>? _matchingItems;
  bool _onlyExpiredSelection = false;
  bool _deletionBlocked = false;
  String? _deleteError;
  bool get _busy => _deleting || _selecting;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.controller.categoryId;
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
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => PopScope(
        canPop: !_deleting,
        child: Scaffold(
          body: AppBackground(
            child: SafeArea(
              // The fade fills the viewport, including the home-indicator area.
              // Keep the final cards safe with scrollable end padding instead.
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) => OverviewHeader(
                          title: _selectedGroup == null
                              ? 'Inventory'
                              : _selectedGroup!.label,
                          actionWidth: constraints.maxWidth < 360 ? 72 : 88,
                          actions: _headerActions(),
                        ),
                      ),
                      if (_deleteMode) _selectionControls(),
                      if (_deleteError != null) _deletionError(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(25, 8, 25, 13),
                        child: IgnorePointer(
                          ignoring: _busy,
                          child: InventoryToolbar(
                            storagePicker: _StoragePill(
                              onScopeChanged: _clearSelection,
                              controller: widget.controller,
                              spacesController: widget.storageSpaceController,
                              pageSize: _selectedGroup == null ? 20 : 100,
                            ),
                            onSearch: _deleting ? () {} : _openSearch,
                            onFilter: _deleting ? () {} : _showFilter,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(25, 0, 25, 8),
                        child: QuantityLegend(),
                      ),
                      Expanded(
                        child: IgnorePointer(
                          ignoring: _busy,
                          child: PageScrollFade(
                            child: AnimatedBuilder(
                              animation: widget.controller,
                              builder: (context, child) =>
                                  _buildContent(context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<InventoryItem> get _visibleItems => _selectedGroup == null
      ? widget.controller.items
      : widget.controller.items.where(_selectedGroup!.includes).toList();

  void _clearSelection() {
    if (_deleting) return;
    setState(() {
      ++_selectionRequest;
      _selecting = false;
      _matchingItems = null;
      _onlyExpiredSelection = false;
      _selected.clear();
      _deleteMode = false;
    });
  }

  void _selectItem(InventoryItem item) {
    if (_busy) return;
    setState(() {
      if (_selected.containsKey(item.id)) {
        _selected.remove(item.id);
      } else {
        _selected[item.id] = item;
        if (!_isExpired(item)) _onlyExpiredSelection = false;
      }
    });
  }

  Widget _headerActions() => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(28),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        Expanded(
          child: IconButton(
            tooltip: 'Add inventory',
            padding: EdgeInsets.zero,
            onPressed: _busy ? null : widget.onAddItemTap,
            icon: const Icon(Icons.add_circle_outline, size: 27),
          ),
        ),
        Expanded(
          child: IconButton(
            tooltip: 'Delete items',
            padding: EdgeInsets.zero,
            onPressed:
                widget.controller.workspace == null ||
                    _busy ||
                    _deletionBlocked ||
                    _deleteMode
                ? null
                : () => setState(() => _deleteMode = true),
            icon: const AppActionIcon(ActionAssets.deleteBlack, size: 26),
          ),
        ),
      ],
    ),
  );

  bool _isExpired(InventoryItem item) {
    final date = item.expiryDate;
    if (date == null) return false;
    final now = DateTime.now();
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).isBefore(DateTime(now.year, now.month, now.day));
  }

  List<InventoryItem> get _selectionScope =>
      _matchingItems ??
      (widget.controller.total <= widget.controller.items.length
          ? _visibleItems
          : const []);

  Future<void> _selectMatching(bool select, {bool expiredOnly = false}) async {
    if (_busy || _deletionBlocked) return;
    final request = ++_selectionRequest;
    setState(() => _selecting = true);
    try {
      final matches = await widget.controller.matchingItems();
      if (!mounted || request != _selectionRequest || !_deleteMode) return;
      final visible = _selectedGroup == null
          ? matches
          : matches.where(_selectedGroup!.includes).toList();
      setState(() {
        _matchingItems = visible;
        final ids = visible.map((item) => item.id).toSet();
        _selected.removeWhere((id, _) => !ids.contains(id));
        if (select && expiredOnly) _selected.clear();
        _onlyExpiredSelection = select && expiredOnly;
        for (final item in visible) {
          if (expiredOnly && !_isExpired(item)) continue;
          if (select) {
            _selected[item.id] = item;
          } else {
            _selected.remove(item.id);
          }
        }
      });
    } catch (error) {
      if (mounted && request == _selectionRequest) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(businessError(error))));
      }
    } finally {
      if (mounted && request == _selectionRequest) {
        setState(() => _selecting = false);
      }
    }
  }

  Widget _selectionControls() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 25),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Delete Selected Items',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        LayoutBuilder(
          builder: (context, constraints) {
            final options = Row(
              children: [
                _selectionOption('All', 'select-all'),
                const SizedBox(width: 12),
                Flexible(
                  child: _selectionOption(
                    'Only expired',
                    'select-all-expired',
                    expiredOnly: true,
                  ),
                ),
              ],
            );
            final labels = TextPainter(
              text: TextSpan(
                text: 'AllOnly expiredConfirmCancel',
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            // Account for checkbox widths, button padding and row gaps.
            final fits = labels.width + 112 <= constraints.maxWidth;
            labels.dispose();
            return fits
                ? Row(
                    children: [
                      Expanded(child: options),
                      const SizedBox(width: 10),
                      _selectionActions(),
                    ],
                  )
                : Column(
                    children: [
                      options,
                      Align(
                        alignment: Alignment.centerRight,
                        child: _selectionActions(),
                      ),
                    ],
                  );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 8),
          child: Text(
            _selecting ? 'Selecting…' : '${_selected.length} selected',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _selectionActions() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      FilledButton(
        key: const Key('batch-delete-confirm'),
        onPressed: _busy || _deletionBlocked || _selected.isEmpty
            ? null
            : () => _deleteItems(_selected.values.toList()),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.text,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text('Confirm'),
      ),
      const SizedBox(width: 8),
      OutlinedButton(
        key: const Key('batch-delete-cancel'),
        onPressed: _deleting ? null : _clearSelection,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          backgroundColor: const Color(0xBFFFFFFF),
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text('Cancel'),
      ),
    ],
  );

  Widget _selectionOption(
    String label,
    String key, {
    bool expiredOnly = false,
  }) {
    final items = expiredOnly
        ? _selectionScope.where(_isExpired).toList()
        : _selectionScope;
    final checked =
        _onlyExpiredSelection == expiredOnly &&
        items.isNotEmpty &&
        items.every((item) => _selected.containsKey(item.id));
    final enabled =
        !_busy &&
        !_deletionBlocked &&
        widget.controller.status == InventoryLoadStatus.loaded;
    void toggle() => _selectMatching(!checked, expiredOnly: expiredOnly);
    return InkWell(
      onTap: enabled ? toggle : null,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              child: Checkbox(
                key: Key(key),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                value: checked,
                activeColor: AppColors.primaryDark,
                onChanged: enabled ? (_) => toggle() : null,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deletionError() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 25),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _deleteError!,
          style: const TextStyle(color: Color(0xFFAE3F24), fontSize: 13),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _deleting ? null : _refreshAfterDeletion,
            child: const Text('Reload inventory'),
          ),
        ),
      ],
    ),
  );

  Widget _inventoryCard(InventoryItem item) {
    final card = InventoryItemTile(
      item: item,
      selected: _selected.containsKey(item.id),
      onTap: () {
        if (!_deleting) {
          if (_deleteMode) {
            _selectItem(item);
          } else {
            _openDetails(item);
          }
        }
      },
      selectionControl: !_deleteMode
          ? null
          : Semantics(
              label: 'Select ${item.itemDefinitionName}',
              child: Checkbox(
                value: _selected.containsKey(item.id),
                activeColor: AppColors.primaryDark,
                onChanged: _deleting ? null : (_) => _selectItem(item),
              ),
            ),
    );
    return _deleteMode || widget.controller.workspace == null
        ? card
        : SwipeDeleteCard(
            key: ValueKey('swipe-${item.id}'),
            itemName: item.itemDefinitionName,
            onDelete: _deleting || _deletionBlocked
                ? null
                : () => _deleteItems([item]),
            child: card,
          );
  }

  Future<void> _refreshAfterDeletion() async {
    if (_busy) return;
    _clearSelection();
    await widget.controller.reload();
    if (!mounted) return;
    if (widget.controller.status == InventoryLoadStatus.loaded ||
        widget.controller.status == InventoryLoadStatus.empty) {
      setState(() {
        _deletionBlocked = false;
        _deleteError = null;
      });
    }
  }

  Future<void> _deleteItems(List<InventoryItem> items) async {
    final workspace = widget.controller.workspace;
    if (workspace == null ||
        items.isEmpty ||
        _busy ||
        _confirmingDelete ||
        _deletionBlocked) {
      return;
    }
    _confirmingDelete = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text(
          items.length == 1 ? 'Delete item?' : 'Delete ${items.length} items?',
        ),
        content: Text(
          '${items.take(3).map((item) => item.itemDefinitionName).join(', ')}${items.length > 3 ? ' and ${items.length - 3} more' : ''}\n\nRemove from inventory? Operation history will be kept.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm delete'),
          ),
        ],
      ),
    );
    _confirmingDelete = false;
    if (!mounted || confirmed != true) return;
    setState(() {
      _deleting = true;
      _deleteError = null;
    });
    var deleted = 0;
    try {
      for (var start = 0; start < items.length; start += 100) {
        final end = (start + 100).clamp(0, items.length);
        final batch = items.sublist(start, end);
        await workspace.archiveItems(batch);
        deleted += batch.length;
        if (!mounted) return;
        setState(() {
          for (final item in batch) {
            _selected.remove(item.id);
          }
        });
      }
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _matchingItems = null;
        _onlyExpiredSelection = false;
        _deleteMode = false;
      });
      await widget.controller.reload();
      if (widget.controller.status == InventoryLoadStatus.empty &&
          widget.controller.page > 1) {
        await widget.controller.loadPage(1);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${items.length} ${items.length == 1 ? 'item' : 'items'} deleted',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _deletionBlocked = true;
          _deleteError =
              '${deleted > 0 ? '$deleted items deleted. ' : ''}${businessError(error)}\nReload inventory before trying again.';
        });
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
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
                itemBuilder: _inventoryCard,
                onRefresh: _refreshAfterDeletion,
              ),
    };
  }

  Future<void> _openSearch() async {
    _clearSelection();
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
    _clearSelection();
    final items = widget.controller.items;
    final categories = <String, String>{};
    for (final item in items) {
      categories[item.categoryId] = item.categoryName;
    }
    showSelectionSheet<String?>(
      context,
      title: 'Filter by category',
      selected: _selectedCategoryId,
      options: [
        ('All categories', null),
        for (final category in categories.entries)
          (category.value, category.key),
      ],
      onSelected: (id) => _applyCategory(id),
    );
  }

  void _applyCategory(String? categoryId) {
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
    this.onScopeChanged,
  });
  final InventoryController controller;
  final StorageSpaceController? spacesController;
  final int pageSize;
  final VoidCallback? onScopeChanged;

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
          onSelected: (id) {
            onScopeChanged?.call();
            controller.loadStorageSpace(id, pageSize: pageSize);
          },
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
    this.itemBuilder,
    this.onRefresh,
  });

  final InventoryController controller;
  final ValueChanged<InventoryItem> onOpenDetails;
  final List<InventoryItem>? items;
  final bool showPagination;
  final Widget Function(InventoryItem)? itemBuilder;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh ?? controller.reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          25,
          8,
          25,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          for (final item in items ?? controller.items)
            Padding(
              key: ValueKey(item.id),
              padding: const EdgeInsets.only(bottom: 13),
              child:
                  itemBuilder?.call(item) ??
                  InventoryItemTile(
                    item: item,
                    onTap: () => onOpenDetails(item),
                  ),
            ),
          if (showPagination && (controller.page > 1 || controller.hasNextPage))
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: controller.page > 1
                        ? () => _loadPage(controller.page - 1)
                        : null,
                    child: const Text('Previous'),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Page ${controller.page}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: controller.hasNextPage
                        ? () => _loadPage(controller.page + 1)
                        : null,
                    child: const Text('Next'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _loadPage(int page) {
    controller.loadPage(page);
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
