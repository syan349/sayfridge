import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A form selector whose options stay readable in a scrollable bottom sheet.
class SelectionField extends FormField<String> {
  SelectionField({
    required String label,
    required Map<String, String> options,
    required ValueChanged<String?>? onChanged,
    String? value,
    String? title,
    InputDecoration? decoration,
    super.validator,
    super.key,
  }) : super(
         initialValue: value,
         enabled: onChanged != null,
         builder: (field) => InkWell(
           borderRadius: BorderRadius.circular(10),
           onTap: onChanged == null
               ? null
               : () async {
                   FocusScope.of(field.context).unfocus();
                   final selected = await showSelectionSheet(
                     field.context,
                     title: title ?? 'Choose ${label.toLowerCase()}',
                     options: options,
                     selected: field.value,
                   );
                   if (!field.mounted ||
                       !field.widget.enabled ||
                       selected == null) {
                     return;
                   }
                   field.didChange(selected);
                   onChanged(selected);
                 },
           child: InputDecorator(
             isEmpty: field.value == null,
             decoration: (decoration ?? InputDecoration(labelText: label))
                 .copyWith(
                   enabled: onChanged != null,
                   errorText: field.errorText,
                 ),
             child: Row(
               children: [
                 Expanded(
                   child: Text(
                     options[field.value] ?? '',
                     maxLines: 1,
                     overflow: TextOverflow.ellipsis,
                   ),
                 ),
                 const SizedBox(width: 8),
                 const Icon(Icons.keyboard_arrow_down, size: 22),
               ],
             ),
           ),
         ),
       );

  @override
  FormFieldState<String> createState() => _SelectionFieldState();
}

class _SelectionFieldState extends FormFieldState<String> {
  @override
  void didUpdateWidget(covariant SelectionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      setValue(widget.initialValue);
    }
  }
}

Future<String?> showSelectionSheet(
  BuildContext context, {
  required String title,
  required Map<String, String> options,
  String? selected,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.background,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.muted,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: options.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No options available'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        indent: 12,
                        endIndent: 12,
                        color: Color(0xFFA8D589),
                      ),
                      itemBuilder: (context, index) {
                        final option = options.entries.elementAt(index);
                        final active = option.key == selected;
                        return Semantics(
                          selected: active,
                          child: Material(
                            color: active
                                ? AppColors.primarySoft
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(13),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(13),
                              onTap: () => Navigator.pop(context, option.key),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 18,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        option.value,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      active
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      size: 23,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  ),
);
