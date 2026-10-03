import 'package:flutter/material.dart';

import '../models/agent_inventory_query.dart';
import '../models/inventory_item.dart';
import '../theme/app_theme.dart';
import 'assistant_widgets.dart';
import 'inventory_visuals.dart';

class AssistantInventoryReply extends StatelessWidget {
  const AssistantInventoryReply({
    required this.message,
    required this.query,
    required this.onItemTap,
    super.key,
  });

  final String message;
  final AgentInventoryQuery query;
  final ValueChanged<InventoryItem> onItemTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AssistantReply(message: message, textStyle: exampleMessageStyle),
      if (query.items.isNotEmpty) const SizedBox(height: 16),
      for (var index = 0; index < query.items.length; index++) ...[
        if (index > 0) const SizedBox(height: 10),
        InventoryItemTile(
          key: ValueKey('assistant-inventory-${query.items[index].id}'),
          item: query.items[index],
          onTap: () => onItemTap(query.items[index]),
        ),
      ],
      if (query.hasMore)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            query.total == null
                ? 'More matching items are available in Inventory.'
                : 'Showing ${query.items.length} of ${query.total} matching batches. See Inventory for more.',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
    ],
  );
}
