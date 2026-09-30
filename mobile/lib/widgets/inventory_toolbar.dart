import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'inventory_visuals.dart';

class InventoryToolbar extends StatelessWidget {
  const InventoryToolbar({
    required this.storagePicker,
    required this.onSearch,
    this.onFilter,
    this.filterTooltip = 'Filter',
    super.key,
  });

  final Widget storagePicker;
  final VoidCallback onSearch;
  final VoidCallback? onFilter;
  final String filterTooltip;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      children: [
        SizedBox(
          width: math.min(116, constraints.maxWidth * 0.34),
          child: storagePicker,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InventoryPill(
            onTap: onSearch,
            child: Row(
              children: [
                Image.asset(HomeAssets.search, width: 21, height: 21),
                const SizedBox(width: 7),
                const Expanded(
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
        ),
        if (onFilter != null) ...[
          const SizedBox(width: 10),
          SizedBox.square(
            dimension: 42,
            child: IconButton(
              tooltip: filterTooltip,
              onPressed: onFilter,
              padding: const EdgeInsets.all(10),
              style: IconButton.styleFrom(backgroundColor: Colors.white),
              icon: Image.asset(HomeAssets.filter, width: 22, height: 22),
            ),
          ),
        ],
      ],
    ),
  );
}

class StoragePickerButton extends StatelessWidget {
  const StoragePickerButton({
    required this.label,
    required this.onTap,
    super.key,
  });
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InventoryPill(
    onTap: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.keyboard_arrow_down, size: 19),
      ],
    ),
  );
}

class InventoryPill extends StatelessWidget {
  const InventoryPill({required this.child, required this.onTap, super.key});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0xFFE6EDDF)),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    ),
  );
}
