import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

Future<void> showSelectionSheet<T>(
  BuildContext context, {
  required String title,
  required List<(String, T)> options,
  required T selected,
  required ValueChanged<T> onSelected,
}) => showModalBottomSheet<void>(
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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .78,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0; index < options.length; index++) ...[
                      if (index > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Divider(color: Color(0xFFA8D589), height: 1),
                        ),
                      SelectionSheetOption(
                        label: options[index].$1,
                        selected: options[index].$2 == selected,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          onSelected(options[index].$2);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

class SelectionSheetOption extends StatelessWidget {
  const SelectionSheetOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    super.key,
  });
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? const Color(0xFFE0F2CE) : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 23,
                color: Colors.black,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
