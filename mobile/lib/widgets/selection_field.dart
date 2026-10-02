import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../repositories/workspace_repository.dart';

/// A form selector whose options stay readable in a scrollable bottom sheet.
class SelectionField extends FormField<String> {
  SelectionField({
    required String label,
    required Map<String, String> options,
    required ValueChanged<String?>? onChanged,
    String? value,
    String? title,
    InputDecoration? decoration,
    Future<String> Function(String name)? onCreateOption,
    Future<void> Function()? onManage,
    bool sortAlphabetically = false,
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
                     onCreateOption: onCreateOption,
                     onManage: onManage,
                     sortAlphabetically: sortAlphabetically,
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

String normalizedSelectionName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

Future<String?> showSelectionSheet(
  BuildContext context, {
  required String title,
  required Map<String, String> options,
  String? selected,
  Future<String> Function(String name)? onCreateOption,
  Future<void> Function()? onManage,
  bool sortAlphabetically = false,
}) async {
  var manage = false;
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _SelectionSheet(
      title: title,
      options: options,
      selected: selected,
      onCreateOption: onCreateOption,
      sortAlphabetically: sortAlphabetically,
      onManage: onManage == null ? null : () => manage = true,
    ),
  );
  if (manage && context.mounted) await onManage!();
  return result;
}

class _SelectionSheet extends StatefulWidget {
  const _SelectionSheet({
    required this.title,
    required this.options,
    this.selected,
    this.onCreateOption,
    this.onManage,
    this.sortAlphabetically = false,
  });
  final String title;
  final Map<String, String> options;
  final String? selected;
  final Future<String> Function(String)? onCreateOption;
  final VoidCallback? onManage;
  final bool sortAlphabetically;
  @override
  State<_SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<_SelectionSheet> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _useName() async {
    final name = _name.text.trim();
    if (_busy) return;
    if (name.isEmpty || name.length > 100) {
      setState(() => _error = 'Enter a category name (up to 100 characters).');
      return;
    }
    final existing = widget.options.entries
        .where(
          (option) =>
              normalizedSelectionName(option.value) ==
              normalizedSelectionName(name),
        )
        .firstOrNull;
    if (existing != null) {
      Navigator.pop(context, existing.key);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.onCreateOption!(name);
      if (mounted) Navigator.pop(context, id);
    } catch (error) {
      if (mounted) setState(() => _error = businessError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options.entries.toList();
    if (widget.sortAlphabetically) {
      options.sort(
        (a, b) => normalizedSelectionName(
          a.value,
        ).compareTo(normalizedSelectionName(b.value)),
      );
    }
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + inset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height - inset - 44) * .75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  widget.title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (widget.onCreateOption != null) ...[
                        TextField(
                          key: const Key('category-name-input'),
                          controller: _name,
                          enabled: !_busy,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: 'Enter category name',
                            errorText: _error,
                            suffixIcon: IconButton(
                              tooltip: 'Use category',
                              onPressed: _busy ? null : _useName,
                              icon: _busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check),
                            ),
                          ),
                          onSubmitted: (_) => _useName(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (options.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No options available'),
                        ),
                      for (var index = 0; index < options.length; index++) ...[
                        if (index > 0)
                          const Divider(
                            height: 1,
                            indent: 12,
                            endIndent: 12,
                            color: Color(0xFFA8D589),
                          ),
                        _option(options[index]),
                      ],
                    ],
                  ),
                ),
                if (widget.onManage != null) ...[
                  const Divider(
                    height: 1,
                    indent: 12,
                    endIndent: 12,
                    color: Color(0xFFA8D589),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.settings_outlined,
                      color: AppColors.text,
                    ),
                    title: const Text('Manage storage spaces'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy
                        ? null
                        : () {
                            widget.onManage!();
                            Navigator.pop(context);
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(MapEntry<String, String> option) {
    final active = option.key == widget.selected;
    return Semantics(
      selected: active,
      child: Material(
        color: active ? AppColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: _busy ? null : () => Navigator.pop(context, option.key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
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
  }
}
