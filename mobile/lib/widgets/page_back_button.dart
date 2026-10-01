import 'package:flutter/material.dart';

/// Align the arrow with the content edge while retaining a full touch target.
class PageBackButton extends StatelessWidget {
  const PageBackButton({this.enabled = true, this.tooltip = 'Back', super.key});

  final bool enabled;
  final String tooltip;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: IconButton(
      onPressed: enabled ? () => Navigator.of(context).maybePop() : null,
      padding: EdgeInsets.zero,
      alignment: Alignment.centerLeft,
      icon: const Icon(Icons.arrow_back_ios_new, size: 23),
      tooltip: tooltip,
    ),
  );
}
