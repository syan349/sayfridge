import 'package:flutter/material.dart';

import '../screens/storage_space_screen.dart';
import '../state/inventory_controller.dart';
import '../state/storage_space_controller.dart';
import '../theme/app_theme.dart';
import 'inventory_visuals.dart';
import 'selection_sheet.dart';

Future<void> showStorageSpacePicker(
  BuildContext context, {
  required String? selectedId,
  required ValueChanged<String?> onSelected,
  StorageSpaceController? spacesController,
  InventoryController? inventoryController,
  Map<String, String> fallbackSpaces = const {},
}) async {
  if (spacesController?.status == StorageSpaceLoadStatus.initial) {
    spacesController!.loadStorageSpaces();
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: ListenableBuilder(
          listenable: Listenable.merge([spacesController, inventoryController]),
          builder: (context, _) {
            final names = <String, String>{...fallbackSpaces};
            for (final item in inventoryController?.items ?? const []) {
              names[item.storageSpaceId] = item.storageSpaceName;
            }
            for (final space in spacesController?.storageSpaces ?? const []) {
              names[space.id] = space.name;
            }
            final inventory = inventoryController;
            final counts = <String, int>{};
            int? total;
            if (inventory != null &&
                (inventory.status == InventoryLoadStatus.loaded ||
                    inventory.status == InventoryLoadStatus.empty) &&
                !inventory.hasItemFilters) {
              if (inventory.storageSpaceId == null) {
                total = inventory.total;
                if (inventory.page == 1 && !inventory.hasNextPage) {
                  for (final id in names.keys) {
                    counts[id] = inventory.items
                        .where((item) => item.storageSpaceId == id)
                        .length;
                  }
                }
              } else {
                counts[inventory.storageSpaceId!] = inventory.total;
              }
            }
            Widget option(String? id, String name, int? count) {
              return SelectionSheetOption(
                label: name,
                subtitle: count == null
                    ? null
                    : '$count ${count == 1 ? 'item' : 'items'}',
                selected: id == selectedId,
                onTap: () {
                  Navigator.pop(sheetContext);
                  onSelected(id);
                },
              );
            }

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 58,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF999999),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 20, 14, 18),
                    child: Text(
                      'Choose storage space',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          option(null, 'All spaces', total),
                          for (final entry in names.entries) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              child: Divider(
                                color: Color(0xFFA8D589),
                                height: 1,
                              ),
                            ),
                            option(entry.key, entry.value, counts[entry.key]),
                          ],
                          if (spacesController?.status ==
                              StorageSpaceLoadStatus.loading)
                            const Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(),
                            ),
                          if (spacesController?.status ==
                              StorageSpaceLoadStatus.error)
                            TextButton(
                              onPressed: spacesController!.loadStorageSpaces,
                              child: const Text(
                                'Could not load spaces. Try again',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (spacesController != null) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Divider(color: Color(0xFFA8D589), height: 1),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      leading: Image.asset(
                        HomeAssets.setting,
                        width: 26,
                        height: 26,
                      ),
                      title: const Text(
                        'Manage storage spaces',
                        style: TextStyle(fontSize: 16),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 27),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => StorageSpaceScreen(
                              controller: spacesController,
                              inventoryController: inventoryController,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
