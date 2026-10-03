import 'inventory_item.dart';

/// A snapshot of authenticated inventory reads attached to one Assistant reply.
class AgentInventoryQuery {
  AgentInventoryQuery.fromJson(Map<String, dynamic> json)
    : items = List.unmodifiable(
        (json['items'] as List).map(
          (row) =>
              InventoryItem.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      ),
      total = json['total'] as int?,
      hasMore = json['has_more'] == true,
      _json = Map.unmodifiable(json);

  final List<InventoryItem> items;
  final int? total;
  final bool hasMore;
  final Map<String, dynamic> _json;

  Map<String, dynamic> toJson() => _json;
}
