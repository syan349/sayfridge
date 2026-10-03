import 'package:flutter/material.dart';

import '../models/item_icon.dart';
import '../models/item_artwork_palette.dart';
import '../theme/app_theme.dart';

class ItemIconPicker extends StatelessWidget {
  const ItemIconPicker({
    required this.name,
    required this.selectedAsset,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String name;
  final String? selectedAsset;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Semantics(
        label: 'Choose item icon',
        button: true,
        child: Material(
          color: Color(
            ItemArtworkPalette.backgroundArgb(
              selectedAsset ?? ItemIcon.forName(name),
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFA8D589)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => _openLibrary(context) : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Image.asset(
                selectedAsset ?? ItemIcon.forName(name),
                key: const Key('item-icon-preview'),
                width: 104,
                height: 104,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
      if (selectedAsset != null) ...[
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: const BorderSide(color: Color(0xFFA8D589)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          onPressed: enabled ? () => onChanged(null) : null,
          child: const Text('Use automatic icon'),
        ),
      ],
    ],
  );

  Future<void> _openLibrary(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final asset = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) =>
          _IconLibrary(selected: selectedAsset ?? ItemIcon.forName(name)),
    );
    if (context.mounted && enabled && asset != null) onChanged(asset);
  }
}

class _IconLibrary extends StatefulWidget {
  const _IconLibrary({required this.selected});
  final String selected;

  @override
  State<_IconLibrary> createState() => _IconLibraryState();
}

class _IconLibraryState extends State<_IconLibrary> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final icons = ItemIcon.library
        .where(
          (icon) =>
              icon.label.toLowerCase().contains(_query) ||
              icon.keywords.any((word) => word.contains(_query)),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height:
              (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              .66,
          child: ListView(
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFA8D589),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Icon library',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close library',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search icons',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, ItemIcon.defaultAsset),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Default icon'),
              ),
              icons.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No matching icons')),
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 105,
                            mainAxisExtent: 100,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: icons.length,
                      itemBuilder: (context, index) {
                        final icon = icons[index];
                        final selected = icon.asset == widget.selected;
                        return Semantics(
                          selected: selected,
                          child: Material(
                            color: Color(
                              ItemArtworkPalette.backgroundArgb(icon.asset),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: selected
                                    ? AppColors.primaryDark
                                    : const Color(0xFFA8D589),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => Navigator.pop(context, icon.asset),
                              child: Padding(
                                padding: const EdgeInsets.all(7),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Image.asset(
                                        icon.asset,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      icon.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
