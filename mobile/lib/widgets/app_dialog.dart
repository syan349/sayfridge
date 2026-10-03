import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared modal treatment. Outlined actions cancel; filled actions continue.
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.actions,
    this.content,
    super.key,
  });

  final Widget title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontFamily: 'Arial',
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    return Theme(
      data: Theme.of(context).copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.text,
            minimumSize: const Size(96, 46),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: const StadiumBorder(),
            textStyle: textStyle,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            minimumSize: const Size(96, 46),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: const StadiumBorder(),
            textStyle: textStyle,
          ),
        ),
      ),
      child: AlertDialog(
        title: title,
        content: content,
        contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        actions: actions,
        actionsAlignment: actions.length > 1
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.end,
        actionsOverflowAlignment: OverflowBarAlignment.start,
        actionsOverflowButtonSpacing: 12,
      ),
    );
  }
}
