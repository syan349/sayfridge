import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_bottom_navigation.dart';
import 'assistant_widgets.dart';

/// Shared welcome design. The caller owns how a suggested message is handled.
class AssistantWelcome extends StatelessWidget {
  const AssistantWelcome({this.onSuggestionSelected, super.key});

  final ValueChanged<String>? onSuggestionSelected;

  @override
  Widget build(BuildContext context) {
    const suggestions = [
      ('I want to update my inventory', AssistantAssets.update),
      ('Add items to my inventory', AssistantAssets.add),
      ('Show me an inventory report', AssistantAssets.report),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 45),
        const Center(
          child: Text(
            'Manage your inventory\nin one conversation',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              height: 1.12,
            ),
          ),
        ),
        const SizedBox(height: 25),
        const Center(
          child: Text(
            'Tell me what you bought, used, moved,\nor want to check..',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 16.5,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 35),
        const Text(
          'Try saying',
          style: TextStyle(color: Color(0xFF707070), fontSize: 16),
        ),
        const SizedBox(height: 11),
        for (var index = 0; index < suggestions.length; index++) ...[
          AssistantSuggestionTile(
            label: suggestions[index].$1,
            asset: suggestions[index].$2,
            onTap: onSuggestionSelected == null
                ? null
                : () => onSuggestionSelected!(suggestions[index].$1),
          ),
          if (index != suggestions.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}
