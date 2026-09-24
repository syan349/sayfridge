import 'inventory_item.dart';

class InventoryPage {
  const InventoryPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<InventoryItem> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasNextPage => page * pageSize < total;

  factory InventoryPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>;

    return InventoryPage(
      items: rawItems
          .map((item) => InventoryItem.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
